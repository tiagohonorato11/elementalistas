# Ondas de inimigos, vitória e derrota. A lógica roda só no host; a fase,
# a onda e os contadores são sincronizados para o HUD de todos.
extends Node3D

const SyncUtil = preload("res://scripts/net/sync_util.gd")

enum Phase { COUNTDOWN, FIGHTING, BREAK, VICTORY, DEFEAT }

const FIRST_COUNTDOWN := 5.0
const BREAK_TIME := 6.0
const SPAWN_INTERVAL := 0.6
# Cada jogador a mais adiciona 50% de inimigos.
const EXTRA_PER_PLAYER := 0.5
const WAVES := [
	{"grunt": 4},
	{"grunt": 5, "archer": 2},
	{"grunt": 4, "archer": 2, "salamander": 2},
	{"grunt": 3, "archer": 3, "salamander": 3, "brute": 1},
	{"grunt": 4, "archer": 3, "salamander": 3, "brute": 2},
]
const SPAWN_POINTS := [
	Vector3(0, 0, -17), Vector3(0, 0, 17), Vector3(-17, 0, 0), Vector3(17, 0, 0),
	Vector3(-14, 0, -14), Vector3(14, 0, -14), Vector3(-14, 0, 14), Vector3(14, 0, 14),
]

var phase: int = Phase.COUNTDOWN
var wave := 0
var timer := FIRST_COUNTDOWN
var enemies_left := 0

var _spawn_queue: Array = []
var _spawn_timer := 0.0
var _enemy_counter := 0


func _ready() -> void:
	SyncUtil.add_sync(self, "StateSync", 1, [".:phase", ".:wave", ".:timer", ".:enemies_left"])


func total_waves() -> int:
	return WAVES.size()


func is_over() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func _process(delta: float) -> void:
	if not multiplayer.is_server() or is_over():
		return

	if phase == Phase.COUNTDOWN or phase == Phase.BREAK:
		timer -= delta
		if timer <= 0.0:
			_start_wave(wave + 1)
	elif phase == Phase.FIGHTING:
		_spawn_timer -= delta
		if not _spawn_queue.is_empty() and _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_INTERVAL
			_spawn_enemy(_spawn_queue.pop_front())
		var alive := _alive_enemies()
		enemies_left = alive + _spawn_queue.size()
		if enemies_left == 0:
			if wave >= WAVES.size():
				phase = Phase.VICTORY
			else:
				phase = Phase.BREAK
				timer = BREAK_TIME
				_revive_everyone()

	if _everyone_down():
		phase = Phase.DEFEAT


func _start_wave(number: int) -> void:
	wave = number
	phase = Phase.FIGHTING
	_spawn_timer = 0.0
	_spawn_queue.clear()
	var scale := 1.0 + EXTRA_PER_PLAYER * (_players().size() - 1)
	var composition: Dictionary = WAVES[number - 1]
	for kind in composition:
		for i in roundi(composition[kind] * scale):
			_spawn_queue.append(kind)
	_spawn_queue.shuffle()
	enemies_left = _spawn_queue.size()


func _spawn_enemy(kind: String) -> void:
	_enemy_counter += 1
	var point: Vector3 = SPAWN_POINTS[_enemy_counter % SPAWN_POINTS.size()]
	get_parent().spawn_entity({"type": "enemy", "kind": kind, "pos": point})


func _alive_enemies() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion():
			count += 1
	return count


func _players() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p): return not p.is_queued_for_deletion())


func _everyone_down() -> bool:
	var players := _players()
	if players.is_empty():
		return false
	for player in players:
		if not player.health.dead:
			return false
	return true


# Entre ondas, quem caiu volta com metade da vida.
func _revive_everyone() -> void:
	for player in _players():
		player.health.revive()
