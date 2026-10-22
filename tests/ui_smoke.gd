# Teste da clareza e do polimento em partida solo (sem janela):
#   godot --headless --path . res://tests/ui_smoke.tscn
# Números de dano e avisos de estado, placar (dano, cura, abates), mira ao segurar
# a tecla, skill negada, ícones (MEGA, dicas), tela de ajuda e tremor da câmera.
extends Node

const E = preload("res://scripts/core/elements.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var dummy: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"
		Network.my_loadouts = {}
		Network.settings["mode"] = "arena"
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		main.game_state.timer = 9999.0
		await _seconds(0.3)
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": Vector3(0, 0, -5)})
		await _seconds(0.2)
		dummy = get_tree().get_nodes_in_group("enemies")[0]
		dummy.set_physics_process(false)
		dummy.health.max_hp = 500.0
		dummy.health.reset()
		await _test_feedback()
		await _test_aim()
		await _test_hud()
		await _test_score()
		print("interface: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		var scene := get_tree().current_scene
		if scene == null or scene.get("local_player") == null or scene.get("game_state") == null:
			return false
		main = scene
		player = main.local_player
		player.camera = null
		return true

	func _texts(unit: Node) -> Array:
		var result: Array = []
		for child in unit.get_children():
			if child.get_script() != null and child.get_script().resource_path.ends_with("floating_text.gd"):
				for label in child.get_children():
					result.append(label.text)
		return result

	func _fresh() -> void:
		player.skill_cooldowns = {}
		player.mana = player.max_mana
		player._clear_queue()

	# --- Números, avisos e placar ---

	func _test_feedback() -> void:
		player.aim_point = dummy.global_position
		await _physics()
		player.request_skill("q", dummy.global_position, "")
		await _seconds(0.6)
		_check("30" in _texts(dummy), "número de dano sobe do alvo (%s)" % [_texts(dummy)])
		_check(is_equal_approx(player.stat_damage, 30.0), "placar conta o dano (%d)" % player.stat_damage)
		dummy.health.frozen = 2.0
		await _seconds(0.1)
		_check("Congelado!" in _texts(dummy), "aviso de estado: Congelado!")
		dummy.health.frozen = 0.0

		player.health.damage(60.0)
		await _seconds(0.3)
		_fresh()
		player.request_skill("w", player.global_position, "")
		await _seconds(0.3)
		_check(player.stat_healing >= 29.0, "placar conta a cura (%d)" % player.stat_healing)
		_check(_texts(player).any(func(text): return text.begins_with("+")), "cura sobe em verde (+)")

		dummy.health.hp = 10.0
		_fresh()
		player.request_skill("q", dummy.global_position, "")
		await _seconds(0.6)
		_check(player.stat_kills == 1, "placar conta o abate (%d)" % player.stat_kills)
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": Vector3(0, 0, -5)})
		await _seconds(0.2)
		dummy = get_tree().get_nodes_in_group("enemies").filter(func(node): return not node.is_queued_for_deletion())[0]
		dummy.set_physics_process(false)

	# --- Mira, alvo do W e skill negada ---

	func _test_aim() -> void:
		var T = E.Type
		_fresh()
		_check(player.aim_shape("q").type == "line" and player.aim_shape("q").end_radius == 0.0, "mira do Q: faixa")
		player.queue.add(T.FIRE)
		player._publish_queue()
		_check(player.aim_shape("q").end_radius > 2.0, "Orbe com carga: mira mostra a explosão")
		_check(player.aim_shape("e").type == "circle" and is_equal_approx(player.aim_shape("e").radius, 3.5), "mira do E: área de 3,5 m")
		player._clear_queue()
		for i in 3:
			player.queue.add(T.SMOKE)
		player._publish_queue()
		_check(player.aim_shape("r").type == "self" and is_equal_approx(player.aim_shape("r").radius, player.MEGA_SMOKE_RADIUS),
			"mira do R: Mega fumaça em volta (12 m)")
		_check(player.aim_shape("w").type == "self", "W segurado: área da bolha")

		# Segurar Q mostra a mira; soltar lança.
		_fresh()
		player.aim_point = dummy.global_position
		_press(KEY_Q, true)
		await _seconds(0.1)
		_check(player._aim_slot == "q" and player._aim_indicator._line.visible, "segurando Q: faixa de mira no chão")
		_check(player.skill_cooldowns.is_empty(), "segurando, a skill ainda não saiu")
		_check(player._aim_indicator._hover.visible, "inimigo sob o mouse ganha um anel (alvo do W)")
		_press(KEY_Q, false)
		await _seconds(0.1)
		_check(player.skill_cooldowns.get("q", 0.0) > 0.0 and not player._aim_indicator._line.visible, "soltar Q lança e esconde a mira")

		# Em recarga: negada (som e o ícone pisca), sem mira.
		_press(KEY_Q, true)
		await _seconds(0.05)
		_check(player.denied.has("q") and player._aim_slot.is_empty(), "skill em recarga é negada")
		_press(KEY_Q, false)
		await _seconds(0.05)

	# --- Ícones, dicas, ajuda e tremor ---

	func _test_hud() -> void:
		var T = E.Type
		var hud: Node = main.hud
		_fresh()
		for i in 3:
			player.queue.add(T.VOID)
		player._publish_queue()
		await _seconds(0.1)
		_check(hud._skill_icons["r"].mega and hud._skill_icons["r"].title == "Apagão", "ícone do R: MEGA dourado (Apagão)")
		_check("MEGA" in hud._skill_icons["r"].tooltip_text, "dica do R explica a MEGA")
		player._clear_queue()
		player.queue.add(T.FIRE)
		player._publish_queue()
		await _seconds(0.1)
		_check("brasa" in hud._skill_icons["e"].tooltip_text, "dica do E mostra a zona da carga (%s)" % hud._skill_icons["e"].tooltip_text)
		_check(hud._slots[0].filled and hud._slots[0].glyph == "fire" and not hud._slots[1].filled, "carga com símbolo do elemento")
		player.skill_cooldowns = {"e": 3.0}
		await _seconds(0.1)
		_check(hud._skill_icons["e"].cooldown_ratio > 0.0 and hud._skill_icons["e"].state == "cooldown", "recarga escurece o ícone")

		_press(KEY_F1, true)
		_press(KEY_F1, false)
		await _seconds(0.1)
		_check(hud.help_panel != null and hud.help_panel.visible and "MEGA" in hud.help_panel.get_child(0).text, "F1 abre a ajuda")
		_press(KEY_F1, true)
		_press(KEY_F1, false)
		await _seconds(0.1)
		_check(not hud.help_panel.visible, "F1 fecha a ajuda")

		main.impact(player.global_position, 1.0)
		_check(main._shake > 0.5 and hud.flash_rect.color.a > 0.0, "impacto grande: tremor e clarão")

	func _test_score() -> void:
		var hud: Node = main.hud
		_check(hud.score_panel == null or not hud.score_panel.visible, "sem placar durante a partida")
		main.game_state.phase = GameState.Phase.VICTORY
		await _seconds(0.1)
		var text: String = hud._score_label.text if hud._score_label != null else ""
		_check(hud.score_panel != null and hud.score_panel.visible and "Mago" in text and "Abates" in text,
			"placar no fim da partida")

	func _press(code: int, down: bool) -> void:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)

	func _check(condition: bool, message: String) -> void:
		print(("ok    " if condition else "FALHOU ") + message)
		if not condition:
			failures += 1

	func _physics() -> void:
		await get_tree().physics_frame

	func _seconds(time: float) -> void:
		await get_tree().create_timer(time).timeout

	func _wait_until(condition: Callable) -> void:
		while not condition.call():
			await get_tree().process_frame


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
