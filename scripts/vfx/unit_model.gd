# Modelo 3D animado de uma unidade (personagem, inimigo ou tropa), filho dela.
# Escolhe a animação pelo que a unidade está fazendo: parada, andando, correndo,
# lançando um feitiço contínuo, uma ação (golpe/tiro) ou caída. Só visual:
# lê estados que já são sincronizados, então funciona igual em todos os PCs.
# Modelos: KayKit (CC0) — ver assets/models/kaykit/CREDITOS.md.
extends Node3D

const ADVENTURERS := "res://assets/models/kaykit/adventurers/"
const SKELETONS := "res://assets/models/kaykit/skeletons/"

# height: altura do modelo original (para escalar até a altura da unidade).
const MODELS := {
	"mage": {"path": ADVENTURERS + "Mage.glb", "height": 2.6,
		"weapons": [[ADVENTURERS + "staff.gltf", "handslot.r"]]},
	"assassin": {"path": ADVENTURERS + "Rogue_Hooded.glb", "height": 2.25,
		"weapons": [[ADVENTURERS + "dagger.gltf", "handslot.r"], [ADVENTURERS + "dagger.gltf", "handslot.l"]]},
	"fighter": {"path": ADVENTURERS + "Barbarian.glb", "height": 2.4,
		"weapons": [[ADVENTURERS + "axe_2handed.gltf", "handslot.r"]]},
	"skeleton_minion": {"path": SKELETONS + "Skeleton_Minion.glb", "height": 2.17, "weapons": []},
	"skeleton_warrior": {"path": SKELETONS + "Skeleton_Warrior.glb", "height": 2.59, "weapons": []},
	"skeleton_rogue": {"path": SKELETONS + "Skeleton_Rogue.glb", "height": 2.31, "weapons": []},
	"skeleton_mage": {"path": SKELETONS + "Skeleton_Mage.glb", "height": 2.63, "weapons": []},
}
const LOOPING := ["Idle", "Walking_A", "Running_A", "Spellcasting", "2H_Melee_Idle"]
const BLEND := 0.15

var model_id := "mage"
var unit_height := 2.0
var unit: Node
var anim: AnimationPlayer
var model: Node3D
var _last_position := Vector3.ZERO
var _speed := 0.0
var _action_count := 0
var _action_lock := 0.0
var _dead_shown := false
var _alpha := 0.0
var _meshes: Array = []
static var _scene_cache := {}


func _ready() -> void:
	unit = get_parent()
	var data: Dictionary = MODELS[model_id]
	model = _load(data.path).instantiate()
	model.scale = Vector3.ONE * (unit_height / data.height)
	model.rotation.y = PI   # os modelos olham para +Z; no jogo a frente é -Z
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	if anim != null:
		for loop_name in LOOPING:
			if anim.has_animation(loop_name):
				anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	_attach_weapons(data.weapons)
	_meshes = model.find_children("*", "GeometryInstance3D", true, false)
	_last_position = global_position
	_play("Idle", 0.0)


static func _load(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


func _attach_weapons(weapons: Array) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	for weapon in weapons:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = weapon[1]
		skeletons[0].add_child(attachment)
		attachment.add_child(_load(weapon[0]).instantiate())


func _process(delta: float) -> void:
	var offset := global_position - _last_position
	offset.y = 0.0
	_last_position = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, offset.length() / delta, 0.3)
	if anim == null:
		return

	if unit.health.dead:
		if not _dead_shown:
			_dead_shown = true
			_play("Death_A")
		return
	_dead_shown = false

	# Ação pontual (golpe, tiro, feitiço instantâneo), avisada pelo contador sincronizado.
	var count = unit.get("action_count")
	if count != null and count != _action_count:
		_action_count = count
		var action: String = unit.action_anim
		if anim.has_animation(action):
			anim.play(action, BLEND)
			_action_lock = anim.get_animation(action).length * 0.8
	if _action_lock > 0.0:
		_action_lock -= delta
		return

	var shape = unit.get("fx_shape")
	if shape != null and shape != 0:
		_play("Spellcasting")
	elif _speed > 3.6:
		_play("Running_A")
	elif _speed > 0.4:
		_play("Walking_A")
	else:
		_play("Idle")


func _play(animation: String, blend := BLEND) -> void:
	if anim.has_animation(animation) and anim.current_animation != animation:
		anim.play(animation, blend)


# Transparência do modelo inteiro (Assassino invisível).
func set_alpha(alpha: float) -> void:
	if is_equal_approx(alpha, _alpha):
		return
	_alpha = alpha
	for mesh in _meshes:
		mesh.transparency = alpha
