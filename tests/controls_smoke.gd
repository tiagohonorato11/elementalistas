# Teste dos controles em partida solo (sem janela):
#   godot --headless --path . res://tests/controls_smoke.tscn
# Simula teclas e cliques de verdade (Input.parse_input_event): carga D F G,
# skills Q W E R, andar clicando (contornando um pilar) e setas.
extends Node

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"
		Network.my_loadouts = {}   # elementos padrão do Mago (não salva)
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		main.game_state.timer = 9999.0   # sem ondas durante o teste
		await _seconds(0.3)
		await _run()
		print("controles: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		main = get_tree().current_scene
		if main == null or main.get("local_player") == null or main.get("game_state") == null:
			return false
		player = main.local_player
		player.camera = null   # a mira (aim_point) é definida pelo teste
		return true

	func _run() -> void:
		var dummy := await _spawn_dummy(Vector3(0, 0, -4))
		player.aim_point = dummy.global_position   # o mouse está sobre o alvo

		# Mago com Fogo, Raio e Arcano (padrão): D = Fogo, F = Raio, G = Arcano.
		var T = E.Type
		_check(player.elements == [T.FIRE, T.LIGHTNING, T.ARCANE], "elementos escolhidos no lobby (%s)" % [player.elements])

		# 1) D F G carregam a carga (até 3); Q lança o Orbe com ela e a consome.
		_key(KEY_D)
		_key(KEY_D)
		_key(KEY_F)
		_key(KEY_G)   # 4º elemento: a carga já está cheia
		await _seconds(0.1)
		_check(player.queue_view == [T.FIRE, T.FIRE, T.LIGHTNING], "D D F carregam Fogo, Fogo, Raio (máximo 3)")
		var mana_before: float = player.mana
		_key(KEY_Q)
		await _seconds(0.5)
		_check(dummy.health.hp < 500.0 - 30.0 and dummy.health.burning > 0.0, "Q: Orbe com a carga acerta e queima (hp=%d)" % dummy.health.hp)
		_check(player.queue_view.is_empty(), "a skill consome a carga")
		_check(player.mana < mana_before and player.skill_cooldowns.get("q", 0.0) > 0.0, "Q gasta mana e entra em recarga")
		var hp_after: float = dummy.health.hp
		_key(KEY_Q)
		await _seconds(0.4)
		_check(dummy.health.burning > 0.0 and dummy.health.hp >= hp_after - 10.0, "em recarga o Q não sai")

		# 2) W com o mouse sobre o inimigo: Maldição (lento + marcado).
		_reset(dummy, Vector3(0, 0, -4))
		player.aim_point = dummy.global_position
		_key(KEY_W)
		await _seconds(0.1)
		_check(dummy.health.slowed > 0.0 and dummy.health.vulnerable > 0.0, "W no inimigo: Maldição")

		# 3) W sem ninguém sob o mouse: Bênção em si mesmo (cura). Espera a recarga.
		await _seconds(8.0)
		player.health.damage(80.0)
		player.aim_point = Vector3(5, 0, 5)
		_key(KEY_G)   # Arcano na carga: vira proteção contra Arcano
		_key(KEY_W)
		await _seconds(0.1)
		_check(player.health.hp >= 200.0 - 80.0 + 29.0 and player.health.ward > 0.0, "W no vazio: Bênção em si mesmo (hp=%d)" % player.health.hp)

		# 4) E: Raio laser contínuo na direção do mouse.
		_reset(dummy, Vector3(0, 0, -6))
		player.aim_point = dummy.global_position
		await _seconds(0.1)
		_key(KEY_E)
		await _seconds(0.5)
		_check(player.fx_shape == SpellResolver.Shape.BEAM and dummy.health.hp < 490.0, "E: Raio laser acerta (hp=%d)" % dummy.health.hp)
		await _seconds(1.3)
		_check(player.fx_shape == SpellResolver.Shape.NONE, "o laser termina sozinho")

		# 5) R sem carga não sai; com carga, sai o ultimate do elemento dominante.
		_key(KEY_R)
		await _seconds(0.1)
		_check(player.skill_cooldowns.get("r", 0.0) == 0.0, "R sem carga não sai")
		_reset(dummy, Vector3(0, 0, -6))
		player.aim_point = dummy.global_position
		_key(KEY_D)
		_key(KEY_R)
		await _seconds(1.4)
		_check(dummy.health.hp < 450.0 and player.skill_cooldowns.get("r", 0.0) > 50.0, "R com Fogo: Meteoro (hp=%d)" % dummy.health.hp)

		# 6) Andar clicando com o botão direito, contornando o pilar em (7, -7).
		dummy.queue_free()
		player.global_position = Vector3(7, 0, -3)
		await _seconds(0.2)
		player.aim_point = Vector3(7, 0, -11)   # atrás do pilar
		_click(MOUSE_BUTTON_RIGHT)
		await _seconds(4.0)
		_check(player.global_position.distance_to(Vector3(7, 0, -11)) < 0.6,
			"clique leva o personagem até o destino, contornando o pilar (%s)" % player.global_position.snapped(Vector3.ONE * 0.1))

		# 7) Clique dentro de um obstáculo: chega o mais perto possível e para.
		player.aim_point = Vector3(7, 0, -7)   # centro do pilar
		_click(MOUSE_BUTTON_RIGHT)
		await _seconds(3.0)
		_check(not player.has_move_target, "destino inalcançável: desiste em vez de ficar empurrando")

		# 8) Setas andam e cancelam o destino do clique.
		player.global_position = Vector3.ZERO
		player.aim_point = Vector3(0, 0, 10)
		_click(MOUSE_BUTTON_RIGHT)
		await _seconds(0.1)
		_press(KEY_LEFT, true)
		await _seconds(0.5)
		_press(KEY_LEFT, false)
		_check(not player.has_move_target and player.global_position.x < -1.5, "seta cancela o clique e anda (%s)" % player.global_position.snapped(Vector3.ONE * 0.1))

	# --- Ajudantes ---

	func _spawn_dummy(at: Vector3) -> Node:
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": at})
		await _seconds(0.2)
		var dummy: Node = get_tree().get_nodes_in_group("enemies")[0]
		dummy.health.max_hp = 500.0
		_reset(dummy, at)
		return dummy

	# Alvo parado: sem física não anda, não vira e não ataca.
	func _reset(dummy: Node, at: Vector3) -> void:
		dummy.set_physics_process(false)
		dummy.health.reset()
		dummy.global_position = at

	func _press(code: int, down: bool) -> void:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)

	func _key(code: int) -> void:
		_press(code, true)
		_press(code, false)

	func _click(button: int) -> void:
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = down
			Input.parse_input_event(event)
			await get_tree().physics_frame

	func _check(condition: bool, message: String) -> void:
		print(("ok    " if condition else "FALHOU ") + message)
		if not condition:
			failures += 1

	func _seconds(time: float) -> void:
		await get_tree().create_timer(time).timeout

	func _wait_until(condition: Callable) -> void:
		while not condition.call():
			await get_tree().process_frame


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
