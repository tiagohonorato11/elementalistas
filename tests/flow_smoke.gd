# Teste do fluxo da partida em modo solo, acelerado (sem janela):
#   godot --headless --path . res://tests/flow_smoke.tscn
# 1) Elimina os inimigos assim que surgem: as 5 ondas devem terminar em VITÓRIA.
# 2) Reinicia e fica parado: os inimigos derrubam o mago e a partida termina em DERROTA.
extends Node

const GameState = preload("res://scripts/gameplay/game_state.gd")


class Driver extends Node:
	var step := 0
	var time := 0.0
	var last_wave := 0
	var failed := false

	func _process(delta: float) -> void:
		time += delta / Engine.time_scale
		var main := get_tree().current_scene
		var state = main.get("game_state") if main != null else null
		if step == 0:
			# Acelera só a parte das ondas; a perseguição é testada em velocidade normal.
			Engine.time_scale = 4.0
			Network.my_class = "mage"
			Network.host()
			Network.start_game()
			step = 1
		elif step == 1 and is_instance_valid(state):
			for enemy in get_tree().get_nodes_in_group("enemies"):
				enemy.health.damage(9999.0)
			if state.wave != last_wave:
				last_wave = state.wave
				print("onda %d começou" % state.wave)
			if state.phase == GameState.Phase.VICTORY:
				print("OK: vitória depois de %d ondas" % state.wave)
				Engine.time_scale = 1.0
				Network.restart_game()
				step = 2
		elif step == 2 and is_instance_valid(state) and state.phase == GameState.Phase.FIGHTING:
			print("reiniciou: onda %d" % state.wave)
			step = 3
		elif step == 3 and is_instance_valid(state) and state.phase == GameState.Phase.DEFEAT:
			print("OK: derrota com o mago caído=%s" % main.local_player.health.dead)
			get_tree().quit(0)
		if time > 120.0:
			printerr("FALHOU: tempo esgotado no passo %d" % step)
			get_tree().quit(1)


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
