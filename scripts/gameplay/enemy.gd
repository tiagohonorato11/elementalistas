# Inimigo controlado pelo host: escolhe o mago vivo mais próximo, anda até ele
# pelo navmesh e ataca corpo a corpo ou à distância. Os outros peers só exibem.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")

const GRAVITY := 20.0
const RETARGET_TIME := 0.5
const REPATH_TIME := 0.25
const PUSH_DECAY := 18.0
const MAX_PUSH := 12.0

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
}

var kind := "grunt"
var info: Dictionary
var health: Health
var label: Label3D
var agent: NavigationAgent3D
var target: Node3D
var attack_timer := 1.0
var push_velocity := Vector3.ZERO
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

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = capsule.height
	body.mesh = mesh
	body.position.y = collision.position.y
	body.material_override = E.make_material(info.color)
	add_child(body)

	# Olhos para mostrar a frente (-Z).
	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.5, 0.12, 0.12) * size
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0.0, 1.45 * size, -0.4 * size)
	eyes.material_override = E.make_material(Color(1.0, 0.95, 0.3))
	add_child(eyes)

	health = Health.new()
	health.name = "Health"
	health.max_hp = info.hp
	health.resistances = info.resist
	add_child(health)

	label = Label3D.new()
	label.position.y = 2.2 * size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	add_child(label)

	if multiplayer.is_server():
		health.died.connect(queue_free)
		agent = NavigationAgent3D.new()
		agent.radius = capsule.radius
		agent.path_desired_distance = 0.5
		agent.target_desired_distance = 0.5
		add_child(agent)

	SyncUtil.add_sync(self, "StateSync", 1, [
		".:position", ".:rotation",
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:frozen",
	])


func _process(_delta: float) -> void:
	label.text = "%s %d\n%s" % [info.label, ceili(health.hp), health.status_text()]


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	attack_timer -= delta
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _is_valid_target(target):
		_retarget_timer = RETARGET_TIME
		target = _nearest_player()

	var direction := Vector3.ZERO
	var frozen := health.frozen > 0.0
	if target != null and not frozen:
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
		if distance <= attack_range and attack_timer <= 0.0:
			_attack()

	var speed: float = info.speed
	if health.chilled > 0.0:
		speed *= 0.5
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
	if info.has("projectile"):
		var forward := -global_transform.basis.z
		get_parent().spawn_entity({
			"type": "projectile",
			"pos": global_position + Vector3.UP * 1.2,
			"dir": forward,
			"elements": info.projectile,
			"caster": String(name),
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


func _is_valid_target(node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion() and not node.health.dead
