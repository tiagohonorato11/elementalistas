# Projétil (Terra/Gelo): voa em linha reta e aplica os elementos no primeiro alvo.
# Em rede: todos movem o projétil localmente; só o host decide acertos e o remove.
extends Node3D

const E = preload("res://scripts/core/elements.gd")

const SPEED := 18.0
const LIFETIME := 3.0

var elements: Array = []
var caster_name := ""
var direction := Vector3.FORWARD
var age := 0.0


func setup(p_elements: Array, p_caster_name: String, p_direction: Vector3) -> void:
	elements = p_elements
	caster_name = p_caster_name
	direction = p_direction.normalized()


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	mesh.mesh = sphere
	mesh.material_override = E.make_material(E.COLORS[elements[0]])
	add_child(mesh)


func _physics_process(delta: float) -> void:
	var step := direction * SPEED * delta
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
		var target_health = hit.collider.get_node_or_null("Health")
		if target_health != null:
			target_health.apply_elements(elements, 1.0)
		queue_free()
		return
	global_position = from + step
