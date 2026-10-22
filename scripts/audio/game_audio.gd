# Sons dos acontecimentos da partida (filho do main, em todos os PCs): trilha
# por contexto, combate esquentando a música, ondas, torres caindo, nível,
# ouro, chefe por perto e a fanfarra do fim. Só lê estado sincronizado.
extends Node

const Combat = preload("res://scripts/core/combat.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")
const Ambience = preload("res://scripts/audio/ambience.gd")

const COMBAT_RANGE := 16.0
const BOSS_RANGE := 15.0
const SCAN_TIME := 0.5

var main: Node
var _phase := -1
var _winner := -1
var _level := -1
var _gold := -1
var _action := -1
var _dead_structures := {}
var _scan := 0.0
var _ambience: Node3D


func _ready() -> void:
	main = get_parent()
	Audio.music(main.mode)
	_ambience = Ambience.new()
	_ambience.main = main
	main.add_child.call_deferred(_ambience)


func _exit_tree() -> void:
	Audio.music("menu")


func _process(delta: float) -> void:
	_watch_state()
	var player: Node = main.local_player
	if not is_instance_valid(player):
		return
	_watch_player(player)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_TIME
		_scan_world(player)


func _watch_state() -> void:
	var state: Node = main.game_state
	if not is_instance_valid(state):
		return
	if main.mode == "practice" or main.mode == "world":
		return
	if main.mode == "moba":
		if state.winner != _winner:
			_winner = state.winner
			if _winner != -1 and is_instance_valid(main.local_player):
				Audio.stinger("victory" if _winner == main.local_player.team else "defeat")
		return
	if state.phase == _phase:
		if state.phase == GameState.Phase.FIGHTING:
			Audio.combat_ping()
		return
	var first := _phase == -1
	_phase = state.phase
	match _phase:
		GameState.Phase.FIGHTING:
			if not first:
				Audio.play("wave_horn")
			Audio.combat_ping()
		GameState.Phase.BREAK:
			Audio.play("bell")
		GameState.Phase.VICTORY:
			Audio.stinger("victory")
		GameState.Phase.DEFEAT:
			Audio.stinger("defeat")


func _watch_player(player: Node) -> void:
	if player.progression:
		if _level != -1 and player.level > _level:
			Audio.play("level_up")
		_level = player.level
		if _gold != -1 and player.gold != _gold:
			# Gastou: compra na loja. Ganhou: moedinhas mais baixas.
			Audio.play("coins", null, 0.0 if player.gold < _gold else -9.0)
		_gold = player.gold
	if player.action_count != _action:
		var first := _action == -1
		_action = player.action_count
		if not first and _enemy_near(player, COMBAT_RANGE):
			Audio.combat_ping()
	if player.fx_shape != 0 and _enemy_near(player, COMBAT_RANGE):
		Audio.combat_ping()


func _scan_world(player: Node) -> void:
	var boss_near := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.kind == "boss" and not enemy.health.dead \
				and enemy.global_position.distance_to(player.global_position) <= BOSS_RANGE:
			boss_near = true
	Audio.set_boss(boss_near)
	for structure in get_tree().get_nodes_in_group("structures"):
		var dead: bool = structure.health.dead
		if dead and not _dead_structures.get(structure.name, false):
			Audio.play("bell")
		_dead_structures[structure.name] = dead


func _enemy_near(player: Node, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == player or node.health.dead:
			continue
		if not Combat.is_hostile(Combat.team_of(player), Combat.team_of(node)):
			continue
		if node.global_position.distance_to(player.global_position) <= radius:
			return true
	return false
