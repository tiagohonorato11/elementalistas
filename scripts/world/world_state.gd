# Estado do modo Mundo (RPG). Sem fim de partida: um mapa aberto para explorar.
# No host: cria os acampamentos de monstros e os faz renascer, dá ouro e xp (e
# progresso de missão) a quem estava perto quando um monstro caiu, e a fonte da
# vila cura. Cair: volta na vila depois de alguns segundos (player.gd).
extends Node3D

const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const WorldMap = preload("res://scripts/world/world_map.gd")
const Quests = preload("res://scripts/world/quests.gd")

const FOUNTAIN_HEAL := 40.0       # vida por segundo na fonte da vila
const SPAWN_SPACING := 1.6

var world_time := 0.0
var _main: Node
var _camp_defs := {}
var _camp_members := {}           # id -> [monstros]
var _camp_timers := {}            # id -> segundos para renascer


func _ready() -> void:
	SyncUtil.add_sync(self, "StateSync", 1, [".:world_time"])


func is_over() -> bool:
	return false


# Chamado pelo main no host, depois de criar os personagens.
func start(main: Node) -> void:
	_main = main
	for camp in WorldMap.CAMPS:
		_camp_defs[camp.id] = camp
		_spawn_camp(camp)


func _process(delta: float) -> void:
	if not multiplayer.is_server() or _main == null:
		return
	world_time += delta
	for player in get_tree().get_nodes_in_group("players"):
		if not player.health.dead and player.global_position.distance_to(WorldMap.FOUNTAIN) <= WorldMap.FOUNTAIN_RADIUS:
			player.health.heal(FOUNTAIN_HEAL * delta)
	for id in _camp_timers.keys():
		_camp_timers[id] -= delta
		if _camp_timers[id] <= 0.0:
			_camp_timers.erase(id)
			_spawn_camp(_camp_defs[id])


# Quanto falta para o acampamento renascer (0 se está de pé). Para testes e HUD.
func respawn_left(camp_id: String) -> float:
	return _camp_timers.get(camp_id, 0.0)


func _spawn_camp(camp: Dictionary) -> void:
	var members := []
	var count: int = camp.kinds.size()
	for i in count:
		var angle := TAU * i / count
		var offset := Vector3(cos(angle), 0, sin(angle)) * (SPAWN_SPACING if count > 1 else 0.0)
		var monster: Node = _main.spawn_entity({
			"type": "enemy", "kind": camp.kinds[i], "team": Combat.NEUTRAL,
			"camp": camp.pos, "pos": camp.pos + offset,
		})
		monster.health.died.connect(_on_monster_died.bind(camp.id, monster))
		members.append(monster)
	_camp_members[camp.id] = members


# Quem estava perto ganha ouro, xp e conta para a missão; o acampamento vazio renasce depois.
func _on_monster_died(camp_id: String, monster: Node) -> void:
	var info: Dictionary = monster.info
	for player in get_tree().get_nodes_in_group("players"):
		if player.health.dead or player.global_position.distance_to(monster.global_position) > Progression.REWARD_RANGE:
			continue
		player.add_rewards(info.get("gold", 0), info.get("xp", 0))
		player.quests = Quests.on_kill(player.quests, monster.kind)
	var alive: Array = []
	for other in _camp_members[camp_id]:
		if is_instance_valid(other) and other != monster and not other.health.dead:
			alive.append(other)
	if alive.is_empty():
		_camp_timers[camp_id] = _camp_defs[camp_id].respawn
