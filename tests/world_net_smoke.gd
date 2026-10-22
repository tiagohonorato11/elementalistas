# Teste de rede do modo Mundo com dois processos no mesmo PC (sem janela):
#   godot --headless --path . res://tests/world_net_smoke.tscn -- --role=host
#   godot --headless --path . res://tests/world_net_smoke.tscn -- --role=client
# O cliente vai até a Anciã e aceita a missão pela rede; depois vai aos campos e o
# host derruba um Carniçal perto dele: o cliente ganha ouro, xp e progresso.
extends Node

const WorldMap = preload("res://scripts/world/world_map.gd")


class Driver extends Node:
	var role := ""
	var time := 0.0
	var step := 0

	var _kill_time := 0.0

	func _process(delta: float) -> void:
		time += delta
		var main := get_tree().current_scene
		if role == "host":
			if step == 0:
				Network.my_class = "mage"
				Network.my_loadouts = {}
				Network.host()
				Network.set_setting("mode", "world")
				step = 1
			elif step == 1 and Network.players.size() >= 2:
				Network.start_game()
				step = 2
			elif step == 2:
				# Quando o cliente chega aos campos, derruba o Carniçal mais perto dele.
				var clients := main.get_children().filter(func(node): return node.is_in_group("players") and node.peer_id != 1)
				if clients.is_empty() or clients[0].global_position.distance_to(Vector3(-21, 0, 2)) > 3.0:
					return
				var client: Node = clients[0]
				var ghouls := get_tree().get_nodes_in_group("enemies").filter(func(node): return node.kind == "ghoul")
				ghouls.sort_custom(func(a, b): return a.global_position.distance_to(client.global_position) \
					< b.global_position.distance_to(client.global_position))
				print("[host] cliente em %s; Carniçal mais perto a %.1f m" % [client.global_position.snapped(Vector3.ONE * 0.1),
					ghouls[0].global_position.distance_to(client.global_position)])
				ghouls[0].health.damage(99999.0)
				_kill_time = time
				step = 3
			elif step == 3 and time > _kill_time + 1.5:
				_report(main)
				step = 4
			elif step == 4 and time > _kill_time + 4.0:
				get_tree().quit()
		else:
			if step == 0 and time > 1.0:
				Network.my_class = "fighter"
				Network.my_loadouts = {}
				Network.join("127.0.0.1")
				step = 1
			elif step == 1 and main != null and main.get("local_player") != null:
				main.local_player.camera = null
				step = 2
			elif step == 2 and time > 5.0:
				main.local_player.global_position = WorldMap.ELDER + Vector3(1.5, 0, 0)
				step = 3
			elif step == 3 and time > 5.6:
				main.local_player.request_quest.rpc_id(1, "accept")
				step = 4
			elif step == 4 and time > 6.5:
				main.local_player.global_position = Vector3(-21, 0, 2)   # perto dos Carniçais
				step = 5
			elif step == 5 and (main.local_player.xp > 0 or time > 14.0):
				_report(main)
				get_tree().quit()

	func _report(main: Node) -> void:
		var lines := PackedStringArray(["[%s] modo=%s" % [role, Network.game_mode()]])
		for child in main.get_children():
			if child.is_in_group("players"):
				lines.append("[%s] %s %s nível=%d xp=%d ouro=%d missões=%s" % [role, child.name, child.cls.label,
					child.level, child.xp, child.gold, child.quests])
		print("\n".join(lines))


func _ready() -> void:
	var driver := Driver.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			driver.role = arg.get_slice("=", 1)
	get_tree().root.add_child.call_deferred(driver)
