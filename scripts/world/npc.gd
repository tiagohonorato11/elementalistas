# Personagem da vila (modo Mundo), parado e só visual (montado em todos os PCs):
# - "elder": Anciã Lira, dá as missões. Mostra "!" quando tem missão nova para
#   você e "?" quando a sua está pronta para entregar.
# - "merchant": Ferreiro Bruno, a loja (tecla B perto dele).
extends Node3D

const Quests = preload("res://scripts/world/quests.gd")

const ADVENTURERS := "res://assets/models/kaykit/adventurers/"
const ROLES := {
	"elder": {"name": "Anciã Lira", "model": "Mage.glb", "height": 2.6, "size": 2.0},
	"merchant": {"name": "Ferreiro Bruno", "model": "Barbarian.glb", "height": 2.4, "size": 2.1},
}

var role := "elder"
var main: Node
var _marker: Label3D


func _ready() -> void:
	var data: Dictionary = ROLES[role]
	var path: String = ADVENTURERS + data.model
	if ResourceLoader.exists(path):
		var model: Node3D = load(path).instantiate()
		model.scale = Vector3.ONE * (data.size / data.height)
		model.rotation.y = PI
		add_child(model)
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim != null and anim.has_animation("Idle"):
			anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
			anim.play("Idle")
	var label := Label3D.new()
	label.text = data.name if role == "elder" else "%s\n(loja)" % data.name
	label.font_size = 40
	label.pixel_size = 0.008
	label.outline_size = 10
	label.modulate = Color(1.0, 0.95, 0.7)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.6
	add_child(label)
	_marker = Label3D.new()
	_marker.font_size = 110
	_marker.pixel_size = 0.01
	_marker.outline_size = 16
	_marker.modulate = Color(1.0, 0.85, 0.2)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = 3.6
	add_child(_marker)


func _process(delta: float) -> void:
	_marker.position.y = 3.6 + 0.12 * sin(Time.get_ticks_msec() / 300.0)
	if role != "elder":
		_marker.text = ""
		return
	var player = main.get("local_player") if main != null else null
	if not is_instance_valid(player):
		_marker.text = ""
		return
	var active := Quests.active(player.quests)
	if not active.is_empty() and Quests.is_complete(player.quests, active):
		_marker.text = "?"
	elif not Quests.next_offer(player.quests).is_empty():
		_marker.text = "!"
	else:
		_marker.text = ""
