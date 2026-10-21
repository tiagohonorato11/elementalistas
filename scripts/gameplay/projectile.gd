# Projétil (Terra/Gelo): voa em linha reta e aplica os elementos no primeiro alvo.
# O poder (carga) multiplica o dano, o tamanho e o empurrão.
# Em rede: todos movem o projétil localmente; só o host decide acertos e o remove.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")

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


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15 + 0.12 * power
	sphere.height = sphere.radius * 2.0
	mesh.mesh = sphere
	mesh.material_override = E.make_material(E.COLORS[elements[0]])
	add_child(mesh)


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
