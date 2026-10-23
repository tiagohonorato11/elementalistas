# Palco 3D do Grimório de combos: o personagem de verdade (modelo, carga e skills
# do jogo) usa a skill escolhida em três esqueletos, em loop. Fica dentro de um
# SubViewport com mundo próprio. Roda offline (este PC é o "host").
extends Node3D

const Main = preload("res://scripts/gameplay/main.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")

const PLAYER_POS := Vector3(-3.0, 0.0, 0.0)
# Esqueletos em volta do alvo (tipos sem "aggro_range": só reagem se provocados).
const MOBS := [["grunt", Vector3(0.0, 0.0, -1.4)], ["archer", Vector3(0.9, 0.0, 1.1)], ["brute", Vector3(1.8, 0.0, -0.2)]]
const MOB_HP := 400.0
const CHARGE_GAP := 0.25        # s entre um toque de D F G e o próximo
const LOOP_TIME := 4.5
const ULTIMATE_LOOP_TIME := 7.0
# Distância do alvo para cada skill (o Golpe giratório precisa estar colado).
const DISTANCES := {"orb": 8.0, "bless_curse": 6.0, "mini_meteor": 8.0, "dagger": 7.0, "veil_mark": 5.0,
	"shadow_step": 6.5, "whirl": 1.8, "shout": 5.0, "charge": 6.5}
# Ultimates que acontecem em volta de quem lança: alvo mais perto.
const SELF_ULTIMATES := ["storm", "frost", "quake", "eclipse", "smokescreen", "blood_moon", "blessing", "fortress",
	"mega_lightning", "mega_cold", "mega_void", "mega_smoke", "mega_blood", "mega_arcane", "mega_life", "mega_shield"]
const FRONT_ULTIMATES := ["tide", "mega_water", "mega_earth"]

# Cada repetição acontece num Round, que faz o papel da cena da partida para as
# entidades (spawn_entity, impact, map_half). Ao trocar, o Round velho some
# inteiro: os esqueletos não soltam a poeira de morte.
class Round extends Node3D:
	var stage: Node3D
	var map_half := Vector2(18.0, 18.0)
	var _counter := 0

	func spawn_entity(data: Dictionary) -> Node:
		_counter += 1
		var node := Main.make_entity(data)
		node.name = "%s%d" % [data.type, _counter]
		node.position = data.pos
		add_child(node)
		return node

	func impact(_at: Vector3, strength: float, _color := Color.WHITE) -> void:
		stage.shake = maxf(stage.shake, strength)


var camera: Camera3D
var caption := ""               # o que a prévia está mostrando (lido pela tela)
var player: Node3D
var shake := 0.0                # tremor da câmera (impactos)
var _round: Round
var _run := 0                   # cada show() começa uma repetição nova; as antigas param
var _camera_base := Vector3.ZERO
var _class_id := "mage"
var _elements: Array = []
var _keys: Array = []
var _slot := "q"


func _ready() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	mesh.material_override = Main.terrain_material(Color(0.35, 0.42, 0.3), true)
	ground.add_child(mesh)
	ground.position.y = -0.5
	add_child(ground)
	Main.add_lights(self)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.current = true


# A tela vai fechar: some com a repetição atual (sem poeira de morte nos esqueletos).
func stop() -> void:
	_run += 1
	if _round != null:
		_round.queue_free()
		_round = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop()


func _process(delta: float) -> void:
	camera.position = _camera_base
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.3
		shake = maxf(shake - 2.5 * delta, 0.0)


func _physics_process(_delta: float) -> void:
	if _round == null:
		return
	# Os esqueletos só apanham: nunca ficam provocados (não atacam nem perseguem).
	for node in _round.get_children():
		if node.is_in_group("enemies"):
			node.aggressive = false
			node.returning = false


# Mostra a skill `slot` da classe com a carga montada apertando `keys` (0 = D, 1 = F, 2 = G).
func show_skill(class_id: String, elements: Array, keys: Array, slot: String) -> void:
	_class_id = class_id
	_elements = elements.duplicate()
	_keys = keys.duplicate()
	_slot = slot
	_loop()


# --- Repetição ---

func _loop() -> void:
	_run += 1
	var run := _run
	var round_number := 0
	while run == _run and is_inside_tree():
		await _play_once(run, round_number)
		round_number += 1


func _play_once(run: int, round_number: int) -> void:
	_new_round()
	var skill := Classes.skill(_class_id, _slot)
	var charge := _charge_preview()
	var distance := _distance(skill, charge)
	var target_at := PLAYER_POS + Vector3(distance, 0, 0)
	_spawn_player()
	var mobs: Array = []
	for mob in MOBS:
		mobs.append(_spawn_mob(mob[0], target_at + mob[1]))
	player.aim_point = target_at
	var middle := (PLAYER_POS + target_at) / 2.0
	var zoom := clampf((distance + 7.0) / 13.0, 0.75, 1.2)
	_camera_base = middle + Vector3(0, 7.5, 9.5) * zoom
	camera.position = _camera_base
	camera.look_at(middle + Vector3.UP * 0.6)

	# W: alterna entre o inimigo e você (Mago: a bolha, segurando a tecla).
	var target_name := ""
	var held := false
	if _slot == "w":
		if round_number % 2 == 0:
			target_name = String(mobs[0].name)
			caption = "%s no inimigo" % skill.label
		elif skill.has("hold"):
			held = true
			caption = "%s segurado: bolha de escudo" % skill.label
		else:
			target_name = String(player.name)
			caption = "%s em você" % skill.label
	elif _slot == "r":
		var id := Ultimates.resolve(charge)
		caption = ("MEGA " if Ultimates.is_mega(charge) else "") + Ultimates.label(id) if not id.is_empty() else ""
	else:
		caption = skill.label

	if not await _wait(run, 0.6):
		return
	for key in _keys:
		player.request_charge(key)
		if not await _wait(run, CHARGE_GAP):
			return
	if not await _wait(run, 0.3):
		return
	if held:
		player.request_skill_held(_slot, target_at, "")
	else:
		player.request_skill(_slot, target_at, target_name)
	await _wait(run, ULTIMATE_LOOP_TIME if _slot == "r" else LOOP_TIME)


# false se outra repetição começou (ou a tela fechou) durante a espera.
func _wait(run: int, time: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(time).timeout
	return run == _run and is_inside_tree()


# A carga que as teclas vão montar (para escolher a distância do alvo).
func _charge_preview() -> Array:
	var queue := ElementQueue.new()
	for key in _keys:
		queue.add(_elements[key])
	return queue.elements


func _distance(skill: Dictionary, charge: Array) -> float:
	if skill.id == "ultimate":
		var id := Ultimates.resolve(charge)
		if id in SELF_ULTIMATES:
			return 4.5
		if id in FRONT_ULTIMATES:
			return 5.0
		return 8.0
	return DISTANCES.get(skill.id, 6.0)


func _new_round() -> void:
	if _round != null:
		_round.queue_free()
	_round = Round.new()
	_round.stage = self
	add_child(_round)
	player = null


func _spawn_player() -> void:
	# O personagem lê o modo de jogo ao nascer: aqui é sempre o da Arena.
	var mode = Network.settings.get("mode")
	Network.settings["mode"] = "arena"
	Combat.friendly_fire = false
	player = Main.make_entity({"type": "player", "bot": true, "id": 1, "class": _class_id,
		"elements": _elements, "color": 0})
	player.name = "Voce"
	player.position = PLAYER_POS
	_round.add_child(player)
	Network.settings["mode"] = mode
	# É um "bot" só para não ler o teclado e o mouse; quem decide o que fazer é o palco.
	var brain := player.get_node_or_null("BotBrain")
	if brain != null:
		brain.free()


func _spawn_mob(kind: String, at: Vector3) -> Node3D:
	var mob := Main.make_entity({"type": "enemy", "kind": kind, "team": Combat.NEUTRAL, "camp": at})
	mob.name = "Esqueleto%d" % _round.get_child_count()
	mob.position = at
	_round.add_child(mob)
	mob.look_at(PLAYER_POS, Vector3.UP)
	mob.health.max_hp = MOB_HP
	mob.health.reset()
	return mob
