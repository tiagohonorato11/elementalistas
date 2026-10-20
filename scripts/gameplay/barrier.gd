# Barreira (Escudo): parede temporária que bloqueia movimento e projéteis.
# Em rede: o host remove a barreira quando o tempo acaba, e ela some para todos.
extends StaticBody3D

const E = preload("res://scripts/core/elements.gd")

const LIFETIME := 6.0
const SIZE := Vector3(3.0, 2.0, 0.4)


func _ready() -> void:
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = SIZE
	collision.shape = box_shape
	collision.position.y = SIZE.y / 2.0
	add_child(collision)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	mesh.mesh = box
	mesh.position.y = SIZE.y / 2.0
	mesh.material_override = E.make_material(Color(1.0, 0.9, 0.5, 0.6))
	add_child(mesh)

	if multiplayer.is_server():
		get_tree().create_timer(LIFETIME).timeout.connect(queue_free)
