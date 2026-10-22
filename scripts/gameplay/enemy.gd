# Inimigo controlado pelo host. Os outros peers só exibem.
# - Arena: escolhe o jogador vivo mais próximo, anda até ele pelo navmesh e ataca.
# - Selva do MOBA (time neutro): fica no acampamento; só ataca quando leva dano,
#   persegue quem estiver perto e, se for longe demais, volta e se cura.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const StatusFx = preload("res://scripts/vfx/status_fx.gd")
const UnitModel = preload("res://scripts/vfx/unit_model.gd")
const HealthBar = preload("res://scripts/vfx/health_bar.gd")
const UnitSounds = preload("res://scripts/audio/unit_sounds.gd")

# Modelo (esqueletos KayKit) e animação de ataque de cada tipo.
const LOOKS := {
	"grunt": ["skeleton_minion", "1H_Melee_Attack_Chop"],
	"archer": ["skeleton_mage", "Spellcast_Shoot"],
	"salamander": ["skeleton_rogue", "Dualwield_Melee_Attack_Slice"],
	"brute": ["skeleton_warrior", "2H_Melee_Attack_Chop"],
	"jungle_wolf": ["skeleton_rogue", "Dualwield_Melee_Attack_Stab"],
	"jungle_golem": ["skeleton_warrior", "2H_Melee_Attack_Chop"],
	"boss": ["skeleton_mage", "Spellcast_Long"],
}

const GRAVITY := 20.0
const RETARGET_TIME := 0.5
const REPATH_TIME := 0.25
const PUSH_DECAY := 18.0
const MAX_PUSH := 12.0
const LEASH_RANGE := 14.0      # selva: distância máxima do acampamento
const JUNGLE_AGGRO := 10.0     # selva: alcance para escolher quem atacar

# Todos os números são nossos e podem ser ajustados livremente.
const KINDS := {
	"grunt": {
		"label": "Lacaio", "hp": 120.0, "speed": 3.2, "scale": 1.0, "color": Color(0.55, 0.6, 0.55),
		"range": 1.6, "cooldown": 1.0, "damage": 15.0, "elements": [], "resist": {},
	},
	"archer": {
		"label": "Arqueiro", "hp": 80.0, "speed": 2.6, "scale": 0.9, "color": Color(0.35, 0.65, 0.8),
		"range": 11.0, "keep_distance": 7.0, "cooldown": 2.5, "damage": 0.0,
		"projectile": [E.Type.ICE], "elements": [], "resist": {},
	},
	"salamander": {
		"label": "Salamandra", "hp": 150.0, "speed": 3.0, "scale": 1.0, "color": Color(0.95, 0.4, 0.15),
		"range": 1.6, "cooldown": 1.2, "damage": 5.0, "elements": [E.Type.FIRE],
		"resist": {E.Type.FIRE: 0.0, E.Type.STEAM: 0.5, E.Type.WATER: 1.5, E.Type.COLD: 1.5, E.Type.ICE: 1.5},
	},
	"brute": {
		"label": "Brutamontes", "hp": 450.0, "speed": 1.8, "scale": 1.6, "color": Color(0.45, 0.3, 0.25),
		"range": 2.2, "cooldown": 2.0, "damage": 40.0, "elements": [], "resist": {E.Type.EARTH: 0.5},
		"push_scale": 0.3,
	},
	# Selva do MOBA.
	"jungle_wolf": {
		"label": "Carniçal", "hp": 320.0, "speed": 3.8, "scale": 0.9, "color": Color(0.5, 0.5, 0.55),
		"range": 1.6, "cooldown": 1.0, "damage": 18.0, "elements": [], "resist": {},
		"gold": 35, "xp": 40,
	},
	"jungle_golem": {
		"label": "Golem", "hp": 950.0, "speed": 2.3, "scale": 1.5, "color": Color(0.45, 0.4, 0.35),
		"range": 2.2, "cooldown": 1.6, "damage": 45.0, "elements": [], "resist": {E.Type.EARTH: 0.5},
		"push_scale": 0.4, "gold": 90, "xp": 110,
	},
	"boss": {
		"label": "Guardião", "hp": 3200.0, "speed": 2.0, "scale": 2.3, "color": Color(0.3, 0.6, 0.5),
		"range": 3.0, "cooldown": 1.8, "damage": 70.0, "elements": [E.Type.EARTH], "resist": {},
		"push_scale": 0.1, "gold": 250, "xp": 300,
	},
}

var kind := "grunt"
var team := Combat.RED            # Arena: o time contrário aos jogadores; selva: NEUTRAL
var camp_position := Vector3.ZERO
var aggressive := false           # selva: provocado
var returning := false            # selva: voltando ao acampamento
var info: Dictionary
var health: Health
var label: Label3D
var agent: NavigationAgent3D
var target: Node3D
var attack_timer := 1.0
var push_velocity := Vector3.ZERO
var action_anim := ""          # animação de ataque, sincronizada pelo host
var action_count := 0
var _retarget_timer := 0.0
var _repath_timer := 0.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemies")
	info = KINDS[kind]
	var size: float = info.scale

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45 * size
	capsule.height = 1.8 * size
	collision.shape = capsule
	collision.position.y = 0.9 * size
	add_child(collision)

	var unit_model := UnitModel.new()
	unit_model.model_id = LOOKS[kind][0]
	unit_model.unit_height = 1.9 * size
	add_child(unit_model)
	# Cor do tipo no chão (e chamas permanentes na Salamandra).
	Vfx.add_ring(self, info.color, capsule.radius + 0.3)
	if kind == "salamander":
		var aura := Vfx.emitter(E.Type.FIRE, {"amount": 16, "lifetime": 0.5, "speed": 1.2,
			"box": Vector3(0.3, 0.6, 0.3), "size_scale": 1.2})
		aura.position.y = 0.9
		aura.emitting = true
		add_child(aura)

	health = Health.new()
	health.name = "Health"
	health.max_hp = info.hp
	health.resistances = info.resist
	add_child(health)

	var status_fx := StatusFx.new()
	status_fx.height = 1.8 * size
	status_fx.radius = 0.45 * size
	add_child(status_fx)

	var bar := HealthBar.new()
	bar.width = 1.0 * size
	bar.height_above = 2.0 * size + 0.2
	add_child(bar)
	var sounds := UnitSounds.new()
	sounds.material = "bone"
	sounds.attack_sound = "" if info.has("projectile") else "slash"
	sounds.attack_volume = -4.0 if kind == "boss" or kind == "brute" or kind == "jungle_golem" else -8.0
	add_child(sounds)

	label = Label3D.new()
	label.position.y = 2.0 * size + 0.55
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	add_child(label)

	if multiplayer.is_server():
		health.died.connect(queue_free)
		health.damaged.connect(_on_damaged)
		agent = NavigationAgent3D.new()
		agent.radius = capsule.radius
		# O navmesh fica 0,5 m acima da origem do inimigo (que está no chão).
		agent.path_height_offset = 0.5
		agent.path_desired_distance = 0.5
		agent.target_desired_distance = 0.5
		add_child(agent)

	SyncUtil.add_sync(self, "StateSync", 1, [
		".:position", ".:rotation",
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:frozen",
		"Health:stunned", "Health:slowed", "Health:vulnerable", "Health:blinded", "Health:bleeding", "Health:silenced", "Health:last_element",
		".:action_anim", ".:action_count",
	])


func _process(_delta: float) -> void:
	label.text = "%s\n%s" % [info.label, health.status_text()]


func is_neutral() -> bool:
	return team == Combat.NEUTRAL


# Selva: levar dano provoca o monstro (se ele não estiver voltando para casa).
func _on_damaged(_amount: float) -> void:
	if is_neutral() and not returning:
		aggressive = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	attack_timer -= delta
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _is_valid_target(target):
		_retarget_timer = RETARGET_TIME
		target = _jungle_target() if is_neutral() else _nearest_player()

	var direction := Vector3.ZERO
	var disabled := health.is_disabled()
	if is_neutral() and (returning or target == null) and not disabled:
		direction = _return_to_camp()
	elif target != null and not disabled:
		var offset := target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		var attack_range: float = info.range
		if info.has("keep_distance"):
			if distance > info.keep_distance:
				direction = _path_direction(delta)
			elif distance < info.keep_distance * 0.6:
				direction = -offset.normalized()
		elif distance > attack_range * 0.9:
			direction = _path_direction(delta)
		if distance > 0.01:
			look_at(global_position + offset, Vector3.UP)
		if distance <= attack_range and attack_timer <= 0.0 and health.blinded <= 0.0:
			_attack()

	var speed: float = info.speed * health.speed_factor()
	velocity.x = direction.x * speed + push_velocity.x
	velocity.z = direction.z * speed + push_velocity.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	push_velocity = push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()


# Empurrão (só no host, que move os inimigos). O brutamontes resiste.
func push(impulse: Vector3) -> void:
	impulse.y = 0.0
	push_velocity = (push_velocity + impulse * info.get("push_scale", 1.0)).limit_length(MAX_PUSH)


# Direção do próximo ponto do caminho; sem navmesh, vai em linha reta.
func _path_direction(delta: float) -> Vector3:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = REPATH_TIME
		agent.target_position = target.global_position
	var next := agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	if agent.is_navigation_finished() or direction.length() < 0.05:
		direction = target.global_position - global_position
		direction.y = 0.0
	return direction.normalized()


func _attack() -> void:
	attack_timer = info.cooldown
	action_anim = LOOKS[kind][1]
	action_count += 1
	if info.has("projectile"):
		var forward := -global_transform.basis.z
		get_parent().spawn_entity({
			"type": "projectile",
			"pos": global_position + Vector3.UP * 1.2,
			"dir": forward,
			"elements": info.projectile,
			"caster": String(name),
			"team": team,
		})
		return
	var target_health: Health = target.get_node("Health")
	if info.damage > 0.0:
		target_health.damage(info.damage)
	if not info.elements.is_empty():
		target_health.apply_elements(info.elements, 1.0)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for player in get_tree().get_nodes_in_group("players"):
		if not _is_valid_target(player):
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


# Ignora caídos e o Assassino invisível.
func _is_valid_target(node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node.health.dead:
		return false
	if node.get("invisible") != null and node.invisible > 0.0:
		return false
	if is_neutral():
		# Selva: não sai de perto do acampamento.
		return aggressive and not returning and node.global_position.distance_to(camp_position) <= LEASH_RANGE
	return true


# Selva: o campeão ou tropa mais próximo (provocou o acampamento); longe demais, volta.
func _jungle_target() -> Node3D:
	if not aggressive or returning:
		return null
	if global_position.distance_to(camp_position) > LEASH_RANGE:
		returning = true
		return null
	var best: Node3D = null
	var best_distance := JUNGLE_AGGRO
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == self or node.is_in_group("structures") or Combat.team_of(node) == Combat.NEUTRAL:
			continue
		if not _is_valid_target(node):
			continue
		var distance := global_position.distance_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	if best == null:
		returning = true
	return best


# Volta ao acampamento; ao chegar, se cura e para de lutar.
func _return_to_camp() -> Vector3:
	var to_camp := camp_position - global_position
	to_camp.y = 0.0
	if to_camp.length() < 1.0:
		if returning:
			returning = false
			aggressive = false
			health.reset()
		return Vector3.ZERO
	if not returning and not aggressive:
		return Vector3.ZERO
	return to_camp.normalized()


# Ao sumir (morte), uma nuvem de poeira em todos os PCs.
func _exit_tree() -> void:
	var parent := get_parent()
	if parent != null and not parent.is_queued_for_deletion():
		Vfx.burst(parent, global_position + Vector3.UP * 0.8, E.Type.STEAM, 20, 0.5, 2.0)
		Audio.play("death_bone", global_position)
