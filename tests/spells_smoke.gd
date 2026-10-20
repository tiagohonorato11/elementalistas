# Teste dos feitiços em partida solo (sem janela):
#   godot --headless --path . res://tests/spells_smoke.tscn
# As ondas ficam pausadas; o teste cria um alvo parado e usa os mesmos pedidos
# que o jogador faz (request_*). Termina com código 0 se tudo passar.
extends Node

const E = preload("res://scripts/core/elements.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"   # os números do teste são os do Mago (não salva)
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		main.game_state.timer = 9999.0   # sem ondas durante o teste
		await _run()
		print("feitiços: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		main = get_tree().current_scene
		if main == null or main.get("local_player") == null or main.get("game_state") == null:
			return false
		player = main.local_player
		player.camera = null
		return true

	func _run() -> void:
		var T = E.Type
		var dummy := await _spawn_dummy(Vector3(0, 0, -6))

		# 1) Projétil carregado: Terra segurada 1,3 s = poder máximo (2x) e empurrão.
		await _cast([T.EARTH], dummy, 1.3)
		await _seconds(0.8)
		_check(500.0 - dummy.health.hp >= 75.0, "projétil carregado causa ~2x de dano (%d)" % (500 - dummy.health.hp))
		_check(dummy.global_position.z < -6.3, "projétil empurra o alvo (z=%.2f)" % dummy.global_position.z)

		# 2) Golpe com Fogo na fila.
		_reset(dummy, player.global_position + Vector3(0, 0, -1.5))
		player.request_element(T.FIRE)
		player.request_weapon(_aim(dummy))
		await _seconds(0.1)
		_check(dummy.health.hp <= 500.0 - 20.0 - 11.0 and dummy.health.burning > 0.0, "golpe com Fogo (hp=%d)" % dummy.health.hp)
		_check(player.queue_view.is_empty(), "golpe consome a fila")

		# 3) Parede de fogo: alvo encostado na barreira queima.
		_reset(dummy, player.global_position + Vector3(0, 0, -3.2))
		await _seconds(0.1)
		await _cast([T.SHIELD, T.FIRE], dummy, 0.0)
		await _seconds(1.0)
		_check(dummy.health.hp < 495.0 and dummy.health.burning > 0.0, "parede de fogo queima quem encosta (hp=%d)" % dummy.health.hp)
		await _seconds(6.0)   # espera a barreira sumir

		# 4) Proteção elemental: Escudo + Fogo em si mesmo.
		player.request_element(T.SHIELD)
		player.request_element(T.FIRE)
		player.request_cast(0 + 2, true, Vector3.FORWARD)   # CastMode.SELF
		var hp_before: float = player.health.hp
		player.health.apply_elements([T.FIRE], 1.0)
		_check(is_equal_approx(player.health.hp, hp_before), "proteção contra Fogo")
		player.health.reset()

		# 5) Congelar: Água e depois Frio em spray.
		_reset(dummy, player.global_position + Vector3(0, 0, -3))
		await _cast([T.WATER], dummy, 0.3)
		_check(dummy.health.wet > 0.0 and dummy.global_position.z < player.global_position.z - 3.3, "spray de Água molha e empurra")
		# A Água empurrou o alvo para longe; traz de volta para o alcance do Frio.
		dummy.push_velocity = Vector3.ZERO
		dummy.global_position = player.global_position + Vector3(0, 0, -3)
		await _seconds(0.1)
		await _cast([T.COLD], dummy, 0.2)
		await _seconds(0.1)
		_check(dummy.health.frozen > 0.0, "Água + Frio congela")

		# 6) Especiais.
		_reset(dummy, player.global_position + Vector3(0, 0, -6))
		for element in [T.FIRE, T.EARTH, T.FIRE, T.EARTH]:
			player.request_element(element)
		player.request_special(dummy.global_position)
		await _seconds(1.3)
		_check(dummy.health.hp < 420.0, "Meteoro (hp=%d)" % dummy.health.hp)
		_check(player.special_cooldowns.get("meteor", 0.0) > 0.0, "Meteoro entra em recarga")
		for element in [T.FIRE, T.EARTH, T.FIRE, T.EARTH]:
			player.request_element(element)
		player.request_special(dummy.global_position)
		_check(player.queue_view.size() == 4, "em recarga não lança (fila mantida)")
		player.request_element(T.ARCANE)   # limpa a fila com anulações
		player._clear_queue()

		_reset(dummy, player.global_position + Vector3(0, 0, -6))
		for element in [T.COLD, T.LIGHTNING, T.COLD, T.LIGHTNING]:
			player.request_element(element)
		player.request_special(dummy.global_position)
		await _seconds(1.2)
		_check(dummy.health.hp < 500.0, "Tempestade (hp=%d)" % dummy.health.hp)

		_reset(dummy, player.global_position + Vector3(0, 0, -6))
		for element in [T.COLD, T.SHIELD, T.COLD]:
			player.request_element(element)
		player.request_special(dummy.global_position)
		await _seconds(0.1)
		_check(dummy.health.frozen > 3.0, "Inverno congela inimigos")

		var start: Vector3 = player.global_position
		for element in [T.ARCANE, T.LIGHTNING, T.ARCANE]:
			player.request_element(element)
		player.request_special(start + Vector3(6, 0, 0))
		await _seconds(0.2)
		_check(player.global_position.distance_to(start + Vector3(6, 0, 0)) < 0.5, "Teleporte (%s)" % player.global_position)

		player.health.damage(150.0)
		for element in [T.LIFE, T.SHIELD, T.LIFE]:
			player.request_element(element)
		player.request_special(player.global_position)
		_check(player.health.hp >= 109.0, "Bênção cura (hp=%d)" % player.health.hp)

	# --- Ajudantes ---

	# Alvo: um lacaio que não anda nem ataca.
	func _spawn_dummy(at: Vector3) -> Node:
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": at})
		await _seconds(0.2)
		var dummy: Node = get_tree().get_nodes_in_group("enemies")[0]
		dummy.info = dummy.info.duplicate()
		dummy.info.speed = 0.0
		dummy.info.damage = 0.0
		dummy.health.max_hp = 500.0
		dummy.health.reset()
		return dummy

	func _reset(dummy: Node, at: Vector3) -> void:
		dummy.health.reset()
		dummy.push_velocity = Vector3.ZERO
		dummy.global_position = at

	func _aim(target: Node) -> Vector3:
		return target.global_position - player.global_position

	# Monta a fila, aperta o botão de lançar, segura e solta.
	func _cast(elements: Array, target: Node, hold: float) -> void:
		# Como o jogador: mira no alvo (o mago vira para o cursor) antes de lançar.
		player.aim_point = target.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		for element in elements:
			player.request_element(element)
		player.request_cast(0, true, _aim(target))
		if hold > 0.0:
			await _seconds(hold)
		player.request_cast(0, false, _aim(target))

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
