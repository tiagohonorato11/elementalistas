# Teste de rede com dois processos no mesmo PC (sem janela):
#   godot --headless --path . res://tests/net_smoke.tscn -- --role=host
#   godot --headless --path . res://tests/net_smoke.tscn -- --role=client
# O cliente lança um projétil de Terra no Dummy3 e anda; os dois lados imprimem o que viram.
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
				Network.host()
				step = 1
			elif step == 1 and Network.players.size() >= 2:
				Network.start_game()
				step = 2
			elif step == 2 and time > 5.5:
				_report(main)
				step = 3
			elif step == 3 and time > 9.0:
				get_tree().quit()
		else:
			if step == 0 and time > 1.0:
				Network.join("127.0.0.1")
				step = 1
			elif step == 1 and main != null and main.get("local_player") != null:
				var player = main.local_player
				player.camera = null
				player.aim_point = player.global_position + Vector3(0, 0, -5)
				player.request_element.rpc_id(1, E.Type.EARTH)
				player.request_cast.rpc_id(1, 0, true)
				player.request_cast.rpc_id(1, 0, false)
				step = 2
			elif step == 2 and time > 3.5:
				main.local_player.global_position = Vector3(3, 0, 1)
				step = 3
			elif step == 3 and time > 6.5:
				_report(main)
				get_tree().quit()

	func _report(main: Node) -> void:
		var lines := PackedStringArray(["[%s] jogadores: %s" % [role, Network.players]])
		for child in main.get_children():
			if String(child.name).begins_with("Player") or String(child.name).begins_with("Dummy"):
				lines.append("[%s] %s pos=%s hp=%d" % [role, child.name, child.position.snapped(Vector3.ONE * 0.1), child.health.hp])
		print("\n".join(lines))


func _ready() -> void:
	var driver := Driver.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			driver.role = arg.get_slice("=", 1)
	get_tree().root.add_child.call_deferred(driver)
