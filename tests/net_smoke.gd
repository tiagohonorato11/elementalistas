# Teste de rede com dois processos no mesmo PC (sem janela):
#   godot --headless --path . res://tests/net_smoke.tscn -- --role=host
#   godot --headless --path . res://tests/net_smoke.tscn -- --role=client
# A onda 1 começa; o cliente (Lutador) carrega Terra, usa o Terremoto (R) e a Investida (E).
# Os dois lados imprimem o que viram (fase, onda, inimigos, magos).
extends Node


class Driver extends Node:
	var role := ""
	var time := 0.0
	var step := 0

	func _process(delta: float) -> void:
		time += delta
		var main := get_tree().current_scene
		if role == "host":
			if step == 0:
				Network.my_class = "mage"
				Network.my_loadouts = {}   # elementos padrão da classe
				Network.host()
				step = 1
			elif step == 1 and Network.players.size() >= 2:
				Network.start_game()
				step = 2
			elif step == 2 and time > 12.5:
				_report(main)
				step = 3
			elif step == 3 and time > 16.0:
				get_tree().quit()
		else:
			if step == 0 and time > 1.0:
				Network.my_class = "fighter"   # o cliente joga de Lutador (não salva)
				Network.my_loadouts = {}   # elementos padrão da classe
				Network.join("127.0.0.1")
				step = 1
			elif step == 1 and main != null and main.get("local_player") != null:
				main.local_player.camera = null
				step = 2
			elif step == 2 and time > 10.0:
				var player = main.local_player
				var enemies := get_tree().get_nodes_in_group("enemies")
				if not enemies.is_empty():
					enemies.sort_custom(func(a, b): return player.global_position.distance_to(a.global_position) \
							< player.global_position.distance_to(b.global_position))
					player.aim_point = enemies[0].global_position
					# Carga pela rede (Lutador: Fogo, Terra, Escudo) e o ultimate de Terra:
					# Terremoto atordoa os inimigos perto.
					player.request_charge.rpc_id(1, 1)
					player.request_charge.rpc_id(1, 1)
					player.request_skill.rpc_id(1, "r", enemies[0].global_position, "")
					print("[client] Terremoto mirando em %s" % enemies[0].name)
					step = 4
			elif step == 4 and time > 11.0 and main.local_player.get("dash_velocity") != null:
				# Investida do Lutador (E): o host pede, o PC do cliente move.
				var from: Vector3 = main.local_player.global_position
				print("[client] investida a partir de %s" % from.snapped(Vector3.ONE * 0.1))
				main.local_player.request_skill.rpc_id(1, "e", from + Vector3(-5, 0, 0), "")
				# Andar clicando no PC do cliente (navmesh local), depois da Investida.
				main.local_player.set_move_target(Vector3(-6, 0, 6))
				step = 5
			elif step == 5 and time > 13.0:
				_report(main)
				get_tree().quit()

	func _report(main: Node) -> void:
		var state = main.game_state
		var lines := PackedStringArray(["[%s] jogadores=%d fase=%d onda=%d restantes=%d" % [
			role, Network.players.size(), state.phase, state.wave, state.enemies_left]])
		for child in main.get_children():
			if child.is_in_group("players") and not child.skill_cooldowns.is_empty():
				lines.append("[%s] %s recargas=%s mana=%d" % [role, child.name, child.skill_cooldowns.keys(), child.mana])
		for child in main.get_children():
			if child.is_in_group("enemies") or child.is_in_group("players"):
				var kind = child.get("kind")
				lines.append("[%s] %s %s pos=%s hp=%d caído=%s atordoado=%s" % [role, child.name, kind if kind else child.cls.label,
						child.position.snapped(Vector3.ONE * 0.1), child.health.hp, child.health.dead, child.health.stunned > 0.0])
		print("\n".join(lines))


func _ready() -> void:
	var driver := Driver.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			driver.role = arg.get_slice("=", 1)
	get_tree().root.add_child.call_deferred(driver)
