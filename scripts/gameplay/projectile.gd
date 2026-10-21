# Projétil (Terra/Gelo): voa em linha reta e aplica os elementos no primeiro alvo.
# O poder (carga) multiplica o dano, o tamanho e o empurrão.
# Em rede: todos movem o projétil localmente; só o host decide acertos e o remove.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const LIFETIME := 3.0
const BASE_PUSH := 2.0
const PUSH_PER_EARTH := 3.0

var elements: Array = []
var caster_name := ""
var team := Combat.NEUTRAL
var direction := Vector3.FORWARD
var power := 1.0
var speed := 18.0
var age := 0.0


func setup(p_elements: Array, p_caster_name: String, p_direction: Vector3,
		p_power := 1.0, p_speed := 18.0, p_team := Combat.NEUTRAL) -> void:
	team = p_team
	elements = p_elements
	caster_name = p_caster_name
	direction = p_direction.normalized()
	power = p_power
	speed = p_speed


var _mesh: MeshInstance3D


func _ready() -> void:
	Audio.play("launch", self, (power - 1.0) * 3.0)
	# Gelo: cristal brilhante; Terra (ou outro): pedra facetada. Cada elemento deixa um rastro.
	_mesh = MeshInstance3D.new()
	var size := 0.15 + 0.12 * power
	if E.Type.ICE in elements:
		var crystal := PrismMesh.new()
		crystal.size = Vector3(size * 1.2, size * 3.0, size * 1.2)
		_mesh.mesh = crystal
		_mesh.rotation.x = -PI / 2.0
		_mesh.material_override = Vfx.glow_material(E.COLORS[E.Type.ICE], 1.5)
	else:
		var rock := SphereMesh.new()
		rock.radius = size
		rock.height = size * 1.8
		rock.radial_segments = 6
		rock.rings = 3
		_mesh.mesh = rock
		var material := StandardMaterial3D.new()
		material.albedo_color = E.COLORS[elements[0]]
		material.roughness = 1.0
		_mesh.material_override = material
	add_child(_mesh)
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)
	var trail_elements: Array = []
	for element in elements:
		if not (element in trail_elements):
			trail_elements.append(element)
	for element in trail_elements:
		var trail := Vfx.emitter(element, {"amount": 24, "lifetime": 0.35, "speed": 0.5, "spread": 180.0,
			"sphere": size * 0.6, "size_scale": 0.9 + 0.3 * power})
		trail.emitting = true
		add_child(trail)


func _process(delta: float) -> void:
	_mesh.rotate_object_local(Vector3.FORWARD, delta * 8.0)


# Impacto: explosão de partículas dos elementos (em todos os PCs, ao sumir).
func _exit_tree() -> void:
	var parent := get_parent()
	if parent == null or parent.is_queued_for_deletion() or elements.is_empty():
		return
	for element in elements.slice(0, 2):
		Vfx.burst(parent, global_position, element, int(16 * power), 0.2, 3.5)
	var impact := "impact_ice" if E.Type.ICE in elements else "impact_rock" if E.Type.EARTH in elements else "impact_magic"
	Audio.play(impact, global_position, (power - 1.0) * 3.0)


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	if not multiplayer.is_server():
		global_position += step
		return

	age += delta
	if age > LIFETIME:
		queue_free()
		return
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + step)
	# Acerta mesmo começando dentro do alvo (inimigo colado no mago).
	query.hit_from_inside = true
	var caster := get_parent().get_node_or_null(caster_name) as CollisionObject3D
	if caster != null:
		query.exclude = [caster.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target: Object = hit.collider
		var target_health = target.get_node_or_null("Health")
		var hit_elements := Combat.filter_elements(team, target, elements)
		if target_health != null and not hit_elements.is_empty():
			target_health.apply_elements(hit_elements, power)
		if target.has_method("push") and Combat.can_harm(team, target):
			var strength := (BASE_PUSH + PUSH_PER_EARTH * elements.count(E.Type.EARTH)) * power
			target.push(direction * strength)
		queue_free()
		return
	global_position = from + step
