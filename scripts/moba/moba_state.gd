# Partida do modo MOBA. A lógica roda só no host; fase, vencedor, tempo e
# contadores são sincronizados para o HUD de todos.
# - cria torres, inibidores, nexus e a selva;
# - solta levas de tropas pelas duas rotas;
# - distribui ouro/xp, cuida das fontes, dos acampamentos e dos bônus;
# - controla a ordem de destruição e o fim da partida (nexus destruído).
extends Node3D

const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const Minion = preload("res://scripts/moba/minion.gd")
const Enemy = preload("res://scripts/gameplay/enemy.gd")

enum Phase { PLAYING, OVER }

const FIRST_WAVE := 15.0
const WAVE_INTERVAL := 30.0
const WAVE := ["melee", "melee", "melee", "ranged", "ranged"]
const INHIBITOR_RESPAWN := 90.0
const FOUNTAIN_HEAL := 60.0       # por segundo, para aliados na fonte
const FOUNTAIN_DAMAGE := 400.0    # por segundo, para inimigos na fonte

var phase: int = Phase.PLAYING
var winner := -1
var game_time := 0.0
var wave_timer := FIRST_WAVE
var boss_timer := 0.0              # > 0: Guardião renascendo

var structures := {}               # id -> nó
var _structure_defs := {}          # id -> dados de moba_map.structures()
var _inhibitor_timers := {}        # id -> segundos para renascer
var _camp_members := {}            # id do acampamento -> [nós]
var _camp_timers := {}             # id do acampamento -> segundos para renascer
var _camp_defs := {}
var _main: Node


func _ready() -> void:
	SyncUtil.add_sync(self, "StateSync", 1, [".:phase", ".:winner", ".:game_time", ".:wave_timer", ".:boss_timer"])


func is_over() -> bool:
	return phase == Phase.OVER


# --- Início (host) -----------------------------------------------------------

func start(main: Node) -> void:
	_main = main
	for definition in MobaMap.structures():
		_structure_defs[definition.id] = definition
		var node: Node = main.spawn_entity({
			"type": "structure", "id": definition.id, "kind": definition.kind,
			"team": definition.team, "lane": definition.lane, "pos": definition.pos,
		})
		structures[definition.id] = node
		node.health.died.connect(_on_structure_died.bind(definition.id))
	_update_invulnerability()
	for camp in MobaMap.camps():
		_camp_defs[camp.id] = camp
		_spawn_camp(camp)


func register_champion(champion: Node) -> void:
	champion.health.died.connect(_on_champion_died.bind(champion))


func champions() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p): return not p.is_queued_for_deletion())


# --- Atualização (host) ------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.is_server() or _main == null or is_over():
		return
	game_time += delta
	wave_timer -= delta
	if wave_timer <= 0.0:
		wave_timer = WAVE_INTERVAL
		_spawn_waves()
	_update_fountains(delta)
	_update_timers(delta)


func _update_fountains(delta: float) -> void:
	for champion in champions():
		if champion.health.dead:
			continue
		for team in [Combat.BLUE, Combat.RED]:
			if champion.global_position.distance_to(MobaMap.fountain(team)) > MobaMap.FOUNTAIN_RADIUS:
				continue
			if team == champion.team:
				champion.health.heal(FOUNTAIN_HEAL * delta)
			else:
				champion.health.damage(FOUNTAIN_DAMAGE * delta)


func _update_timers(delta: float) -> void:
	for id in _inhibitor_timers.keys():
		_inhibitor_timers[id] -= delta
		if _inhibitor_timers[id] <= 0.0:
			_inhibitor_timers.erase(id)
			structures[id].rebuild()
			_update_invulnerability()
	for id in _camp_timers.keys():
		_camp_timers[id] -= delta
		if id == "guardiao":
			boss_timer = maxf(_camp_timers[id], 0.0)
		if _camp_timers[id] <= 0.0:
			_camp_timers.erase(id)
			_spawn_camp(_camp_defs[id])


# --- Tropas ------------------------------------------------------------------

func _spawn_waves() -> void:
	for team in [Combat.BLUE, Combat.RED]:
		for lane in MobaMap.LANES:
			var kinds := WAVE.duplicate()
			# Inibidor inimigo destruído nesta rota: uma supertropa a mais.
			var enemy_key: String = MobaMap.TEAM_KEYS[Combat.RED if team == Combat.BLUE else Combat.BLUE]
			if structures["%s_%s_inibidor" % [enemy_key, lane]].health.dead:
				kinds.push_front("super")
			# Fila para a frente, ao longo da rota (longe do nexus e da torre dele).
			var path := MobaMap.lane_path(team, lane)
			var forward: Vector3 = (path[1] - path[0]).normalized()
			for i in kinds.size():
				var minion: Node = _main.spawn_entity({
					"type": "minion", "kind": kinds[i], "team": team, "lane": lane,
					"pos": path[0] + forward * ((kinds.size() - 1 - i) * 1.3),
				})
				minion.health.died.connect(_on_unit_died.bind(minion))


# --- Selva -------------------------------------------------------------------

func _spawn_camp(camp: Dictionary) -> void:
	var members := []
	for i in camp.count:
		var offset := Vector3(cos(TAU * i / camp.count), 0, sin(TAU * i / camp.count)) * (1.5 if camp.count > 1 else 0.0)
		var monster: Node = _main.spawn_entity({
			"type": "enemy", "kind": camp.kind, "team": Combat.NEUTRAL,
			"camp": camp.pos, "pos": camp.pos + offset,
		})
		monster.health.died.connect(_on_monster_died.bind(camp.id, monster))
		members.append(monster)
	_camp_members[camp.id] = members
	if camp.id == "guardiao":
		boss_timer = 0.0


func _on_monster_died(camp_id: String, monster: Node) -> void:
	var info: Dictionary = monster.info
	var takers := _champions_near(monster.global_position, Combat.NEUTRAL)
	for champion in takers:
		champion.add_rewards(info.get("gold", 0), info.get("xp", 0))
	var alive: Array = _camp_members[camp_id].filter(func(m): return is_instance_valid(m) and m != monster and not m.health.dead)
	if not alive.is_empty():
		return
	var camp: Dictionary = _camp_defs[camp_id]
	_camp_timers[camp_id] = camp.respawn
	if takers.is_empty():
		return
	if camp.kind == "jungle_golem":
		for champion in takers:
			champion.add_buff("golem")
	elif camp.kind == "boss":
		# O Guardião abençoa o time inteiro de quem estava mais perto.
		var team: int = _nearest(takers, monster.global_position).team
		for champion in champions():
			if champion.team == team:
				champion.add_buff("guardiao")
				champion.add_rewards(150, 0)


# --- Mortes e recompensas ----------------------------------------------------

func _on_unit_died(unit: Node) -> void:
	for champion in _champions_near(unit.global_position, unit.team):
		champion.add_rewards(unit.info.gold, unit.info.xp)


func _on_champion_died(victim: Node) -> void:
	if is_over():
		return
	for champion in _champions_near(victim.global_position, victim.team):
		champion.add_rewards(Progression.CHAMPION_KILL_GOLD, Progression.CHAMPION_KILL_XP_PER_LEVEL * victim.level)


func _on_structure_died(id: String) -> void:
	var definition: Dictionary = _structure_defs[id]
	var gold := 0
	if definition.kind == "tower":
		gold = Progression.TOWER_GOLD
	elif definition.kind == "inhibitor":
		gold = Progression.INHIBITOR_GOLD
		_inhibitor_timers[id] = INHIBITOR_RESPAWN
	elif definition.kind == "nexus":
		phase = Phase.OVER
		winner = Combat.RED if definition.team == Combat.BLUE else Combat.BLUE
	for champion in champions():
		if Combat.is_hostile(champion.team, definition.team):
			champion.add_rewards(gold, gold / 2)
	_update_invulnerability()


# Cada estrutura fica protegida até cair alguma das listadas em "requires".
func _update_invulnerability() -> void:
	for id in structures:
		var requires: Array = _structure_defs[id].requires
		if requires.is_empty():
			continue
		var open := false
		for other in requires:
			open = open or structures[other].health.dead
		structures[id].health.invulnerable = not open


# Campeões vivos perto de `point` que são inimigos de `victim_team` (neutro: todos).
func _champions_near(point: Vector3, victim_team: int) -> Array:
	return champions().filter(func(champion): return not champion.health.dead \
		and Combat.is_hostile(champion.team, victim_team) \
		and champion.global_position.distance_to(point) <= Progression.REWARD_RANGE)


func _nearest(nodes: Array, point: Vector3) -> Node:
	var best: Node = null
	var best_distance := INF
	for node in nodes:
		var distance: float = node.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


# --- Consultas para o HUD (todos os peers) ----------------------------------

# Estruturas de pé por time, contando pelos nós sincronizados.
func standing(team: int, kind: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("structures"):
		if node.team == team and node.kind == kind and not node.health.dead:
			count += 1
	return count
