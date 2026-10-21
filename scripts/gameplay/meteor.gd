# Feitiço especial Meteoro: uma marca aparece no chão, a rocha cai e explode
# aplicando Fogo + Terra em área e empurrando tudo para longe (aliados também).
# Em rede: todos animam a queda; só o host aplica o dano e remove o meteoro.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const FALL_TIME := 1.0
const START_HEIGHT := 14.0
const RADIUS := 4.5
const ELEMENTS := [E.Type.FIRE, E.Type.FIRE, E.Type.EARTH, E.Type.EARTH]
const PUSH := 9.0
const LINGER := 0.4

var team := Combat.NEUTRAL
var age := 0.0
var exploded := false
var rock: MeshInstance3D
var marker: MeshInstance3D


func _ready() -> void:
	Audio.play("whoosh", self, 2.0)
	marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.04
	marker.mesh = disc
	marker.material_override = Vfx.glow_material(Color(1.0, 0.3, 0.1), 1.0, 0.25)
	marker.position.y = 0.04
	add_child(marker)

	rock = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	sphere.radial_segments = 7
	sphere.rings = 4
	rock.mesh = sphere
	rock.material_override = Vfx.glow_material(Color(0.9, 0.35, 0.1), 1.2)
	rock.position.y = START_HEIGHT
	add_child(rock)
	var trail := Vfx.emitter(E.Type.FIRE, {"amount": 60, "lifetime": 0.5, "speed": 3.0, "direction": Vector3.UP,
		"sphere": 0.7, "size_scale": 2.5})
	trail.emitting = true
	rock.add_child(trail)


func _process(delta: float) -> void:
	age += delta
	if exploded:
		return
	rock.position.y = lerpf(START_HEIGHT, 0.5, minf(age / FALL_TIME, 1.0))
	if age >= FALL_TIME:
		_explode()


func _explode() -> void:
	exploded = true
	rock.visible = false
	marker.material_override = Vfx.glow_material(Color(1.0, 0.45, 0.1), 1.5, 0.3)
	Vfx.burst(get_parent(), global_position + Vector3.UP * 0.5, E.Type.FIRE, 120, 1.5, RADIUS * 2.0)
	Vfx.burst(get_parent(), global_position + Vector3.UP * 0.5, E.Type.EARTH, 60, 1.0, RADIUS * 1.6)
	Audio.play("explosion", global_position, 3.0)
	Audio.play("crunch", global_position)
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("damageable"):
		var offset: Vector3 = node.global_position - global_position
		offset.y = 0.0
		if offset.length() > RADIUS or not Combat.can_harm(team, node):
			continue
		node.get_node("Health").apply_elements(ELEMENTS, 1.0)
		if node.has_method("push") and offset.length() > 0.01:
			node.push(offset.normalized() * PUSH)
	get_tree().create_timer(LINGER).timeout.connect(queue_free)
