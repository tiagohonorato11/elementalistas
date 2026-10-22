# Teste de rede do modo Treino com dois processos no mesmo PC (sem janela):
#   godot --headless --path . res://tests/practice_net_smoke.tscn -- --role=host
#   godot --headless --path . res://tests/practice_net_smoke.tscn -- --role=client
# O cliente liga "Sem recarga" pelo painel, troca para Assassino (Vazio, Gravidade,
# Sangue) no meio do treino e joga a Adaga num boneco. Os dois lados imprimem o que viram.
extends Node

const E = preload("res://scripts/core/elements.gd")


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
				Network.my_loadouts = {}
				Network.host()
				Network.set_setting("mode", "practice")
				step = 1
			elif step == 1 and Network.players.size() >= 2:
				Network.start_game()
				step = 2
			elif step == 2 and time > 9.0:
				_report(main)
				step = 3
			elif step == 3 and time > 11.0:
				get_tree().quit()
		else:
			if step == 0 and time > 1.0:
				Network.my_class = "mage"
				Network.my_loadouts = {}
				Network.join("127.0.0.1")
				step = 1
			elif step == 1 and main != null and main.get("local_player") != null and main.get("game_state") != null:
				main.local_player.camera = null
				step = 2
			elif step == 2 and time > 5.0:
				main.game_state.request_option.rpc_id(1, "no_cooldowns", true)
				main.game_state.request_loadout.rpc_id(1, "assassin", [E.Type.VOID, E.Type.GRAVITY, E.Type.BLOOD])
				step = 3
			elif step == 3 and time > 6.0 and is_instance_valid(main.local_player) and main.local_player.class_id == "assassin":
				var player = main.local_player
				var dummy: Node = get_tree().get_nodes_in_group("dummies")[0]
				player.request_charge.rpc_id(1, 2)   # Sangue
				player.request_skill.rpc_id(1, "q", dummy.global_position, "")
				print("[client] agora sou %s com %s; Adaga em %s" % [player.cls.label, player.elements, dummy.name])
				step = 4
			elif step == 4 and time > 8.5:
				_report(main)
				get_tree().quit()

	func _report(main: Node) -> void:
		var lines := PackedStringArray(["[%s] modo=%s sem_recarga=%s" % [role, Network.game_mode(), main.game_state.no_cooldowns]])
		for child in main.get_children():
			if child.is_in_group("players"):
				lines.append("[%s] %s %s elementos=%s recargas=%s" % [role, child.name, child.cls.label, child.elements, child.skill_cooldowns])
			elif child.is_in_group("dummies"):
				lines.append("[%s] %s %s dano=%d sangrando=%s" % [role, child.name, child.kind, child.total_damage, child.health.bleeding > 0.0])
		print("\n".join(lines))


func _ready() -> void:
	var driver := Driver.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			driver.role = arg.get_slice("=", 1)
	get_tree().root.add_child.call_deferred(driver)
