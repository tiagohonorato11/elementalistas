# Tropa do MOBA: segue a rota até o nexus inimigo e luta com o que encontrar.
# Prioridade de alvo: tropas inimigas, depois campeões, depois estruturas.
# Em rede: o host move e decide os ataques; os outros peers só exibem.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const Combat = preload("res://scripts/core/combat.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const StatusFx = preload("res://scripts/vfx/status_fx.gd")
const UnitModel = preload("res://scripts/vfx/unit_model.gd")
const HealthBar = preload("res://scripts/vfx/health_bar.gd")
const UnitSounds = preload("res://scripts/audio/unit_sounds.gd")

const LOOKS := {
	"melee": ["skeleton_minion", "1H_Melee_Attack_Chop"],
	"ranged": ["skeleton_mage", "Spellcast_Shoot"],
	"super": ["skeleton_warrior", "2H_Melee_Attack_Chop"],
}

const GRAVITY := 20.0
const AGGRO_RANGE := 8.0
const RETARGET_TIME := 0.4
const WAYPOINT_REACHED := 1.5
const PUSH_DECAY := 18.0
const MAX_PUSH := 10.0

const KINDS := {
	"melee": {"label": "Tropa", "hp": 300.0, "speed": 3.4, "range": 1.7, "cooldown": 1.0,
		"damage": 14.0, "scale": 0.8, "gold": 20, "xp": 30},
	"ranged": {"label": "Atiradora", "hp": 200.0, "speed": 3.4, "range": 6.0, "cooldown": 1.4,
		"damage": 20.0, "scale": 0.7, "gold": 16, "xp": 25},
	"super": {"label": "Supertropa", "hp": 1200.0, "speed": 3.0, "range": 2.2, "cooldown": 1.2,
		"damage": 45.0, "scale": 1.2, "gold": 60, "xp": 80},
}

var kind := "melee"
var team := Combat.BLUE
var path: Array = []          # pontos da rota (moba_map.lane_path)
var info: Dictionary
var health: Health
var target: Node3D
var waypoint := 0
var attack_timer := 0.5
var push_velocity := Vector3.ZERO
var action_anim := ""
var action_count := 0
var _retarget_timer := 0.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("minions")
	info = KINDS[kind]
	var size: float = info.scale

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4 * size
	capsule.height = 1.6 * size
	collision.shape = capsule
	collision.position.y = 0.8 * size
	add_child(collision)

	var unit_model := UnitModel.new()
	unit_model.model_id = LOOKS[kind][0]
	unit_model.unit_height = 1.8 * size
	add_child(unit_model)
	Vfx.add_ring(self, Combat.TEAM_COLORS[team], capsule.radius + 0.3)

	health = Health.new()
	health.name = "Health"
	health.max_hp = info.hp
	add_child(health)

	var status_fx := StatusFx.new()
	status_fx.height = 1.6 * size
	status_fx.radius = 0.4 * size
	add_child(status_fx)

	var bar := HealthBar.new()
	bar.width = 0.9
	bar.height_above = 1.9 * size + 0.15
	add_child(bar)
	var sounds := UnitSounds.new()
	sounds.material = "bone"
	sounds.attack_sound = "" if kind == "ranged" else "whoosh"
	sounds.attack_volume = -10.0
	add_child(sounds)

	if multiplayer.is_server():
		health.died.connect(queue_free)
		# Nasce no primeiro trecho da rota: já segue para o segundo ponto.
		waypoint = 1

	SyncUtil.add_sync(self, "StateSync", 1, [
		".:position", ".:rotation", "Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:frozen",
		"Health:stunned", "Health:slowed", "Health:vulnerable", "Health:blinded", ".:action_anim", ".:action_count",
	])


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or health.dead:
		return
	attack_timer -= delta
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _is_valid_target(target, AGGRO_RANGE + 3.0):
		_retarget_timer = RETARGET_TIME
		target = _pick_target()

	var direction := Vector3.ZERO
	if not health.is_disabled():
		if target != null:
			var offset := target.global_position - global_position
			offset.y = 0.0
			var reach: float = info.range + _target_radius(target)
			if offset.length() > reach * 0.9:
				direction = offset.normalized()
			elif attack_timer <= 0.0 and health.blinded <= 0.0:
				_attack()
			if offset.length() > 0.01:
				look_at(global_position + offset, Vector3.UP)
		elif waypoint < path.size():
			var to_point: Vector3 = path[waypoint] - global_position
			to_point.y = 0.0
			if to_point.length() < WAYPOINT_REACHED:
				waypoint += 1
			else:
				direction = to_point.normalized()
				look_at(global_position + direction, Vector3.UP)

	var speed: float = info.speed * health.speed_factor()
	velocity.x = direction.x * speed + push_velocity.x
	velocity.z = direction.z * speed + push_velocity.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	push_velocity = push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()


func push(impulse: Vector3) -> void:
	impulse.y = 0.0
	var scale := 0.4 if kind == "super" else 1.0
	push_velocity = (push_velocity + impulse * scale).limit_length(MAX_PUSH)


func _attack() -> void:
	attack_timer = info.cooldown
	action_anim = LOOKS[kind][1]
	action_count += 1
	target.health.damage(info.damage)
	if kind == "ranged":
		show_shot.rpc(target.global_position)


func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("damageable"):
		if not _is_valid_target(node, AGGRO_RANGE):
			continue
		var distance := global_position.distance_to(node.global_position)
		var priority := 0.0
		if node.is_in_group("structures"):
			priority = 2000.0
		elif not node.is_in_group("minions"):
			priority = 1000.0
		if distance + priority < best_score:
			best_score = distance + priority
			best = node
	return best


func _is_valid_target(node, max_range: float) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node == self:
		return false
	var other_team := Combat.team_of(node)
	if not Combat.is_hostile(team, other_team) or other_team == Combat.NEUTRAL:
		return false
	if node.health.dead or (node.get("invisible") != null and node.invisible > 0.0):
		return false
	if node.is_in_group("structures") and node.health.invulnerable:
		# Estrutura protegida: segue em frente pela rota.
		return false
	return global_position.distance_to(node.global_position) <= max_range + _target_radius(node)


func _target_radius(node: Node) -> float:
	if node.is_in_group("structures"):
		return node.info.radius
	return 0.5


@rpc("any_peer", "call_local", "reliable")
func show_shot(at: Vector3) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	var from := global_position + Vector3.UP * 1.2
	var to := at + Vector3.UP
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, maxf(from.distance_to(to), 0.1))
	beam.mesh = box
	beam.material_override = Vfx.glow_material(Combat.TEAM_COLORS[team].lightened(0.3), 3.0)
	get_parent().add_child(beam)
	beam.global_position = (from + to) / 2.0
	if from.distance_to(to) > 0.1:
		beam.look_at(to, Vector3.UP)
	get_tree().create_timer(0.1).timeout.connect(beam.queue_free)
	Audio.play("minion_shot", from)


func _exit_tree() -> void:
	var parent := get_parent()
	if parent != null and not parent.is_queued_for_deletion():
		Vfx.burst(parent, global_position + Vector3.UP * 0.6, E.Type.STEAM, 14, 0.4, 1.5)
		Audio.play("death_bone", global_position, -4.0)
