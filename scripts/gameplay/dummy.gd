# Boneco de treino: recebe dano, mostra vida/estados e se regenera ao "morrer".
# Em rede: o host calcula a vida e a sincroniza para todos.
extends StaticBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")

var health: Health
var label: Label3D


func _ready() -> void:
	add_to_group("damageable")

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.0, 2.0, 1.0)
	collision.shape = box_shape
	collision.position.y = 1.0
	add_child(collision)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	mesh.mesh = box
	mesh.position.y = 1.0
	mesh.material_override = E.make_material(Color(0.8, 0.3, 0.3))
	add_child(mesh)

	health = Health.new()
	health.name = "Health"
	health.max_hp = 500.0
	add_child(health)
	if multiplayer.is_server():
		health.died.connect(health.reset)

	label = Label3D.new()
	label.position.y = 2.6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	add_child(label)

	SyncUtil.add_sync(self, "StateSync", 1, [
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:shielded",
	])


func _process(_delta: float) -> void:
	label.text = "%d HP\n%s" % [ceili(health.hp), health.status_text()]
