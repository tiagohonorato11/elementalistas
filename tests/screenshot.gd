# Capturas de tela para conferir o visual (precisa de janela, não roda com --headless):
#   godot --path . res://tests/screenshot.tscn -- --mode=arena --out=C:/caminho/captura
# Arena: usa Orbe, Mini meteoro, Maldição, bolha de escudo e Meteoro (Mago) em alvos com estados.
# MOBA: tira fotos das rotas com tropas, de uma base e do centro da selva.
# Lobby (--mode=lobby): a tela inicial.
# Grimório (--mode=combos): a tela de combos com cada classe e skill.
# Treino (--mode=practice): bonecos com o medidor de dano e o painel de testes.
# Mundo (--mode=world): vila, campos, cemitério, covil e bosque.
extends Node


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
		if mode == "lobby":
			await _lobby_shot()
			return
		if mode == "combos":
			await _combos_shots()
			return
		Network.my_class = "mage"
		Network.my_loadouts = {}   # elementos padrão da classe
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
		elif mode == "practice":
			await _practice_shots()
		elif mode == "world":
			await _world_shots()
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
			enemy.health.max_hp = 999.0
			enemy.health.reset()
			targets.append(enemy)
		targets[0].health.burning = 99.0
		targets[1].health.frozen = 99.0
		targets[2].health.wet = 99.0
		player.health.shielded = 99.0
		var center: Vector3 = targets[1].global_position
		player.aim_point = center
		# Mago com Fogo, Raio e Arcano (slots 0, 1, 2).
		await _cast([0, 0], "q", center, 0.18, "orbe")
		await _seconds(1.0)
		await _cast([0, 0], "e", center, 1.0, "mini_meteoro")
		await _seconds(1.0)
		player.skill_cooldowns = {}
		player.request_charge(2)
		player.request_skill_held("w", center, "")
		await _seconds(0.3)
		await _shot("bolha")
		await _seconds(1.5)
		await _cast([2], "w", center, 0.1, "maldicao", String(targets[1].name))
		await _seconds(1.0)
		player._clear_queue()
		player.request_charge(0)
		player.request_charge(1)
		await _seconds(0.3)
		await _shot("carga")
		player.request_skill("r", center, "")
		await _seconds(1.05)
		await _shot("meteoro")
		# Mira do E (segurando a tecla) com Fogo, e do R com 3 iguais (MEGA).
		await _seconds(1.5)
		player.skill_cooldowns = {}
		player.request_charge(0)
		player._aim_slot = "e"
		player.aim_point = center + Vector3(2, 0, 0)
		await _seconds(0.3)
		await _shot("mira")
		player._aim_slot = ""
		player._clear_queue()
		for i in 3:
			player.request_charge(1)
		player._aim_slot = "r"
		await _seconds(0.3)
		await _shot("mira_mega")
		player._aim_slot = ""
		main.hud._toggle_help()
		await _seconds(0.3)
		await _shot("ajuda")
		main.hud._toggle_help()
		main.game_state.phase = 3   # vitória: mostra o placar
		await _seconds(0.6)
		await _shot("placar")

	# Mundo: a vila (com a conversa da Anciã), os campos, o cemitério e o covil.
	func _world_shots() -> void:
		await _seconds(1.0)
		await _shot("vila")
		player.global_position = Vector3(-5, 0, 22.5)
		await _seconds(0.6)
		await _shot("anciã")
		for spot in [["campos", Vector3(-24, 0, 8)], ["cemiterio", Vector3(24, 0, 12)], ["covil", Vector3(11, 0, -16)],
				["bosque", Vector3(-16, 0, -18)]]:
			player.global_position = spot[1]
			await _seconds(0.8)
			await _shot(spot[0])

	func _practice_shots() -> void:
		var dummy: Node = get_tree().get_nodes_in_group("dummies")[0]
		player.aim_point = dummy.global_position
		await _seconds(0.3)
		await _cast([0, 0], "q", dummy.global_position, 0.6, "treino")
		await _cast([1], "e", dummy.global_position, 1.2, "treino_meteoro")

	# Tela inicial com a escolha de classe e de elementos.
	func _lobby_shot() -> void:
		Network.command_line_used = true
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		await _seconds(0.8)
		await _shot("lobby")
		get_tree().quit()

	# Grimório: uma carga e uma skill de cada classe, no meio da animação.
	func _combos_shots() -> void:
		Network.command_line_used = true
		Network.my_loadouts = {}
		get_tree().change_scene_to_file("res://scenes/combos.tscn")
		await _seconds(0.5)
		var screen := get_tree().current_scene
		for shot in [["mage", 1, "q", 1.2], ["mage", 9, "e", 1.6], ["mage", 18, "r", 1.6], ["mage", 4, "w", 2.6],
				["assassin", 7, "e", 0.9], ["assassin", 12, "r", 1.6], ["fighter", 5, "q", 0.8],
				["fighter", 14, "r", 1.5]]:
			screen._on_class_pressed(shot[0])
			screen._on_combo_pressed(shot[1])
			screen.select_slot(shot[2])
			await _seconds(shot[3])
			await _shot("%s_%s_%d" % [shot[0], shot[2], shot[1]])
		get_tree().quit()

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

	# Carrega os slots dados (0 = D, 1 = F, 2 = G), usa a skill e tira a foto depois de `wait`.
	func _cast(slots: Array, skill: String, at: Vector3, wait: float, name_: String, target := "") -> void:
		player.skill_cooldowns = {}
		player.mana = player.max_mana
		for slot in slots:
			player.request_charge(slot)
		player.request_skill(skill, at, target)
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
