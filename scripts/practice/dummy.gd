# Boneco de treino (modo Treino): não persegue ninguém, só serve de alvo.
# - "dummy": Boneco comum.
# - "armored": Boneco blindado (40% de armadura, resiste a empurrões).
# - "fighter": Boneco que revida: bate em quem chegar perto (para testar escudos,
#   cegueira, roubo de vida...).
# Todos têm mana (para testar o Vazio), voltam à vida cheia 4 s depois do último
# dano, renascem 2 s depois de cair e medem o dano recebido (total e DPS dos
# últimos 5 s). Com "Bonecos andam" ligado no painel, andam de um lado para o outro.
# Em rede: o host simula; os outros só exibem.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const StatusFx = preload("res://scripts/vfx/status_fx.gd")
const UnitModel = preload("res://scripts/vfx/unit_model.gd")
const HealthBar = preload("res://scripts/vfx/health_bar.gd")

const KINDS := {
	"dummy": {"label": "Boneco", "hp": 1000.0, "armor": 0.0, "model": "skeleton_minion", "scale": 1.0,
		"color": Color(0.8, 0.75, 0.5)},
	"armored": {"label": "Boneco blindado", "hp": 1500.0, "armor": 0.4, "model": "skeleton_warrior", "scale": 1.3,
		"color": Color(0.55, 0.6, 0.7), "push_scale": 0.3},
	"fighter": {"label": "Boneco que revida", "hp": 1000.0, "armor": 0.0, "model": "skeleton_rogue", "scale": 1.0,
		"color": Color(0.85, 0.35, 0.3), "damage": 20.0, "cooldown": 1.5, "range": 2.5,
		"attack_anim": "Dualwield_Melee_Attack_Slice"},
}
const ORDER := ["dummy", "armored", "fighter"]

const GRAVITY := 20.0
const PUSH_DECAY := 18.0
const MAX_PUSH := 12.0
const RESET_AFTER := 4.0       # sem levar dano: volta à vida e mana cheias
const RESPAWN_TIME := 2.0
const DPS_WINDOW := 5.0
const WALK_RANGE := 4.0        # anda até 4 m para cada lado de onde foi posto
const WALK_SPEED := 3.0
const MAX_MANA := 100.0

var kind := "dummy"
var team := Combat.RED
var home := Vector3.ZERO
var info: Dictionary
var health: Health
var label: Label3D
var push_velocity := Vector3.ZERO
var mana := MAX_MANA
var max_mana := MAX_MANA
var total_damage := 0.0        # sincronizados para o texto acima do boneco
var dps := 0.0
var action_anim := ""
var action_count := 0
var _hits: Array = []          # [tempo, dano]
var _clock := 0.0
var _since_hit := 0.0
var _respawn := 0.0
var _attack_timer := 0.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemies")
	add_to_group("dummies")
	info = KINDS[kind]
	var size: float = info.scale
	rotation.y = PI   # de frente para o centro da arena

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45 * size
	capsule.height = 1.8 * size
	collision.shape = capsule
	collision.position.y = 0.9 * size
	add_child(collision)

	var unit_model := UnitModel.new()
	unit_model.model_id = info.model
	unit_model.unit_height = 1.9 * size
	add_child(unit_model)
	Vfx.add_ring(self, info.color, capsule.radius + 0.3)

	health = Health.new()
	health.name = "Health"
	health.max_hp = info.hp
	health.armor = info.armor
	add_child(health)

	var status_fx := StatusFx.new()
	status_fx.height = 1.8 * size
	status_fx.radius = 0.45 * size
	add_child(status_fx)
	var bar := HealthBar.new()
	bar.width = 1.0 * size
	bar.height_above = 2.0 * size + 0.2
	add_child(bar)

	label = Label3D.new()
	label.position.y = 2.0 * size + 1.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.009
	label.outline_size = 12
	add_child(label)

	if multiplayer.is_server():
		home = global_position
		health.damaged.connect(_on_damaged)
		health.died.connect(func(): _respawn = RESPAWN_TIME)

	SyncUtil.add_sync(self, "StateSync", 1, [
		".:position", ".:rotation", ".:mana", ".:total_damage", ".:dps", ".:action_anim", ".:action_count",
		"Health:hp", "Health:dead", "Health:wet", "Health:burning", "Health:chilled", "Health:frozen",
		"Health:shielded", "Health:stunned", "Health:slowed", "Health:vulnerable", "Health:blinded",
		"Health:bleeding", "Health:silenced", "Health:hasted", "Health:fortified", "Health:barrier_hp",
		"Health:last_element",
	])


func _process(_delta: float) -> void:
	var lines := PackedStringArray([info.label, "Dano: %d | DPS: %d" % [roundi(total_damage), roundi(dps)]])
	if mana < max_mana:
		lines.append("Mana: %d" % roundi(mana))
	var status := health.status_text()
	if not status.is_empty():
		lines.append(status)
	label.text = "\n".join(lines)


func _on_damaged(amount: float) -> void:
	_since_hit = 0.0
	total_damage += amount
	_hits.append([_clock, amount])


# Zera o medidor de dano (botão do painel).
func reset_meter() -> void:
	total_damage = 0.0
	dps = 0.0
	_hits = []


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_clock += delta
	_since_hit += delta
	_update_dps()
	if health.dead:
		_respawn -= delta
		if _respawn <= 0.0:
			health.reset()
			mana = max_mana
			global_position = home
			push_velocity = Vector3.ZERO
		return
	if _since_hit >= RESET_AFTER and (health.hp < health.max_hp or mana < max_mana):
		health.hp = health.max_hp
		mana = max_mana
	if info.has("damage"):
		_fight(delta)

	var direction := Vector3.ZERO
	var state: Node = get_parent().get("game_state")
	if state != null and state.get("dummies_move") and not health.is_disabled():
		# Vai e volta na linha de onde foi posto (para treinar a mira).
		var goal := home + Vector3(sin(_clock * WALK_SPEED / WALK_RANGE) * WALK_RANGE, 0.0, 0.0)
		var offset := goal - global_position
		offset.y = 0.0
		direction = offset.normalized() * minf(offset.length() * 2.0, 1.0)
	var speed := WALK_SPEED * health.speed_factor()
	velocity.x = direction.x * speed + push_velocity.x
	velocity.z = direction.z * speed + push_velocity.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	push_velocity = push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()


func _update_dps() -> void:
	while not _hits.is_empty() and _clock - _hits[0][0] > DPS_WINDOW:
		_hits.pop_front()
	if _hits.is_empty():
		dps = 0.0
		return
	var sum := 0.0
	for hit in _hits:
		sum += hit[1]
	dps = sum / clampf(_clock - _hits[0][0], 1.0, DPS_WINDOW)


# Boneco que revida: bate no personagem mais perto (não ataca cego, atordoado
# nem quem está invisível).
func _fight(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0 or health.is_disabled() or health.blinded > 0.0:
		return
	var best: Node3D = null
	var best_distance: float = info.range
	for player in get_tree().get_nodes_in_group("players"):
		if player.health.dead or player.invisible > 0.0:
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = player
	if best == null:
		return
	_attack_timer = info.cooldown
	var offset := best.global_position - global_position
	offset.y = 0.0
	if offset.length() > 0.01:
		look_at(global_position + offset, Vector3.UP)
	action_anim = info.attack_anim
	action_count += 1
	best.health.damage(info.damage)


func push(impulse: Vector3) -> void:
	impulse.y = 0.0
	push_velocity = (push_velocity + impulse * info.get("push_scale", 1.0)).limit_length(MAX_PUSH)
