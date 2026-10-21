# Capturas de tela para conferir o visual (precisa de janela, não roda com --headless):
#   godot --path . res://tests/screenshot.tscn -- --mode=arena --out=C:/caminho/captura
# Arena: lança spray, beam, arco, projétil e meteoro em alvos com estados.
# MOBA: tira fotos das rotas com tropas, de uma base e do centro da selva.
extends Node

const E = preload("res://scripts/core/elements.gd")


class Driver extends Node:
	var out := "user://captura"
	var mode := "arena"
	var main: Node
	var player: Node

	func _ready() -> void:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--out="):
				out = arg.get_slice("=", 1)
			elif arg.begins_with("--mode="):
				mode = arg.get_slice("=", 1)
		Network.my_class = "mage"
		Network.settings = {"mode": mode, "bots": true}
		Network.host()
		Network.start_game()
		while not _scene_ready():
			await get_tree().process_frame
		await _seconds(0.5)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--zoom="):
				main.zoom = arg.get_slice("=", 1).to_float()
		if mode == "moba":
			await _moba_shots()
		else:
			await _arena_shots()
		get_tree().quit()

	func _scene_ready() -> bool:
		main = get_tree().current_scene
		if main == null or main.get("local_player") == null or main.get("game_state") == null:
			return false
		player = main.local_player
		player.camera = null
		return true

	func _arena_shots() -> void:
		main.game_state.timer = 9999.0
		var targets := []
		for at in [Vector3(-2.5, 0, -5), Vector3(0, 0, -6), Vector3(2.5, 0, -5)]:
			main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": at})
		await _seconds(0.3)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
			targets.append(enemy)
		targets[0].health.burning = 99.0
		targets[1].health.frozen = 99.0
		targets[2].health.wet = 99.0
		player.health.shielded = 99.0
		var center: Vector3 = targets[1].global_position
		player.aim_point = center
		await _cast([E.Type.FIRE, E.Type.FIRE], 1.35, "spray")
		await _seconds(2.0)
		await _cast([E.Type.ARCANE, E.Type.FIRE], 1.4, "beam")
		await _seconds(2.0)
		await _cast([E.Type.LIGHTNING], 1.35, "arco")
		await _seconds(2.0)
		await _cast([E.Type.EARTH, E.Type.FIRE], 1.07, "projetil")
		await _seconds(1.0)
		await _cast([E.Type.SHIELD, E.Type.FIRE], 1.15, "parede")
		await _seconds(1.0)
		for element in [E.Type.FIRE, E.Type.EARTH, E.Type.FIRE, E.Type.EARTH]:
			player.request_element(element)
		player.request_special(center)
		await _seconds(1.05)
		await _shot("meteoro")

	func _moba_shots() -> void:
		Engine.time_scale = 3.0
		await _seconds(22.0)
		Engine.time_scale = 1.0
		# Onde está a luta mais perto do meio da rota norte.
		var front := Vector3(0, 0, -24)
		var best := INF
		for minion in get_tree().get_nodes_in_group("minions"):
			if minion.global_position.z < 0 and absf(minion.global_position.x) < best:
				best = absf(minion.global_position.x)
				front = minion.global_position
		player.global_position = front + Vector3(0, 0, 3)
		await _seconds(0.6)
		await _shot("rota")
		player.global_position = Vector3(-46, 0, 0)
		await _seconds(0.6)
		await _shot("base")
		player.global_position = Vector3(0, 0, 6)
		await _seconds(0.6)
		await _shot("selva")

	func _cast(elements: Array, wait: float, name_: String) -> void:
		for element in elements:
			player.request_element(element)
		await _seconds(wait)
		await _shot(name_)

	func _shot(name_: String) -> void:
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [out, name_]
		get_viewport().get_texture().get_image().save_png(path)
		print("captura: %s" % path)

	func _seconds(time: float) -> void:
		await get_tree().create_timer(time).timeout


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
