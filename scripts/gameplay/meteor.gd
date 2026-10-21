# Meteoro: uma marca aparece no chão, a rocha cai e explode em área.
# - Ultimate Meteoro: Fogo + Terra, empurra tudo para longe (aliados também).
# - Mini meteoro (E do Mago, `mini`): dano + a carga no impacto e, se houver
#   carga, deixa uma zona com o efeito de cada elemento (zone.gd).
# Em rede: todos animam a queda; só o host aplica o dano e remove o meteoro.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const FALL_TIME := 1.0
const MINI_FALL_TIME := 0.6
const START_HEIGHT := 14.0
const RADIUS := 4.5
const ELEMENTS := [E.Type.FIRE, E.Type.FIRE, E.Type.EARTH, E.Type.EARTH]
const PUSH := 9.0
const MINI_PUSH := 4.0
const LINGER := 0.4
const ZONE_TIME := 3.0

var team := Combat.NEUTRAL
var caster_name := ""
var extra: Array = []          # outros elementos da carga (reforço)
var zone_elements: Array = []  # elementos que deixam zona no impacto
var strength := 1.0            # força do ultimate / poder de quem lançou
var mini := false
var elements: Array = []       # mini: a carga
var damage := 0.0              # mini: dano do impacto
var radius := RADIUS
var zone_time := ZONE_TIME
var age := 0.0
var exploded := false
var rock: MeshInstance3D
var marker: MeshInstance3D


func _ready() -> void:
	Audio.play("whoosh", self, 0.0 if mini else 2.0)
	var color := _color()
	marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	marker.mesh = disc
	marker.material_override = Vfx.glow_material(color, 1.0, 0.25)
	marker.position.y = 0.04
	add_child(marker)

	rock = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45 if mini else 0.8
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 7
	sphere.rings = 4
	rock.mesh = sphere
	rock.material_override = Vfx.glow_material(color, 1.2)
	rock.position.y = START_HEIGHT
	add_child(rock)
	for element in _trail_elements():
		var trail := Vfx.emitter(element, {"amount": 40 if mini else 60, "lifetime": 0.5, "speed": 3.0,
			"direction": Vector3.UP, "sphere": sphere.radius * 0.9, "size_scale": 1.6 if mini else 2.5})
		trail.emitting = true
		rock.add_child(trail)


func _color() -> Color:
	if mini and not elements.is_empty():
		return Vfx.mix_color(elements)
	return Color(1.0, 0.3, 0.1) if not mini else Color(0.75, 0.45, 0.3)


func _trail_elements() -> Array:
	if not mini:
		return [E.Type.FIRE]
	var result: Array = []
	for element in (elements if not elements.is_empty() else [E.Type.EARTH]):
		if not (element in result):
			result.append(element)
	return result


func _fall_time() -> float:
	return MINI_FALL_TIME if mini else FALL_TIME


func _process(delta: float) -> void:
	age += delta
	if exploded:
		return
	rock.position.y = lerpf(START_HEIGHT, 0.5, minf(age / _fall_time(), 1.0))
	if age >= _fall_time():
		_explode()


func _explode() -> void:
	exploded = true
	rock.visible = false
	marker.material_override = Vfx.glow_material(_color().lightened(0.2), 1.5, 0.3)
	for element in _trail_elements().slice(0, 2):
		Vfx.burst(get_parent(), global_position + Vector3.UP * 0.5, element, 120 if not mini else 60, 1.0, radius * 2.0)
	Vfx.burst(get_parent(), global_position + Vector3.UP * 0.5, E.Type.EARTH, 60 if not mini else 30, 1.0, radius * 1.6)
	Audio.play("explosion", global_position, 0.0 if mini else 3.0)
	Audio.play("crunch", global_position)
	if not multiplayer.is_server():
		return
	var dealt := 0.0
	for node in get_tree().get_nodes_in_group("damageable"):
		var offset: Vector3 = node.global_position - global_position
		offset.y = 0.0
		if offset.length() > radius or not Combat.can_harm(team, node):
			continue
		var health: Node = node.get_node("Health")
		if mini:
			dealt += health.damage(damage * strength)
			dealt += health.apply_elements(Combat.filter_elements(team, node, elements), strength)
		else:
			dealt += health.apply_elements(Combat.filter_elements(team, node, ELEMENTS + extra), strength)
		if node.has_method("push") and offset.length() > 0.01:
			node.push(offset.normalized() * (MINI_PUSH if mini else PUSH))
	var caster := get_parent().get_node_or_null(caster_name)
	if caster != null and caster.has_method("drain"):
		caster.drain(dealt, elements if mini else extra)
	var lingering := elements if mini else zone_elements
	if not lingering.is_empty() and get_parent().has_method("spawn_entity"):
		get_parent().spawn_entity({"type": "zone", "pos": global_position, "team": team, "caster": caster_name,
			"elements": lingering, "strength": strength, "radius": radius, "duration": zone_time})
	get_tree().create_timer(LINGER).timeout.connect(queue_free)
