# Teste das classes em partida solo (sem janela):
#   godot --headless --path . res://tests/classes_smoke.tscn
# Joga com Assassino, Lutador e Mago (reiniciando a partida entre eles) usando
# os mesmos pedidos que o jogador faz. Termina com código 0 se tudo passar.
extends Node

const E = preload("res://scripts/core/elements.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var failures := 0

	func _ready() -> void:
		await _start("assassin")
		await _test_assassin()
		await _start("fighter")
		await _test_fighter()
		await _start("mage")
		await _test_mage()
		print("classes: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	# Escolhe a classe sem salvar no PC e (re)inicia a partida.
	func _start(class_id: String) -> void:
		Network.my_class = class_id
		if not Network.is_online():
			Network.host()
			Network.start_game()
		else:
			Network.classes[1] = class_id
			Network.restart_game()
		var old_id := main.get_instance_id() if main != null else 0
		await _wait_until(func(): return _scene_ready(old_id))
		main.game_state.timer = 9999.0   # sem ondas durante o teste
		player.global_position = Vector3.ZERO
		await _seconds(0.2)

	func _scene_ready(old_id: int) -> bool:
		var scene := get_tree().current_scene
		if scene == null or scene.get_instance_id() == old_id or scene.get("local_player") == null or scene.get("game_state") == null:
			return false
		main = scene
		player = main.local_player
		player.camera = null
		return true

	func _test_assassin() -> void:
		var T = E.Type
		_check(player.cls.label == "Assassino" and is_equal_approx(player.health.max_hp, 140.0), "Assassino: 140 de vida")
		var dummy := await _spawn_dummy(Vector3(0, 0, -1.5), PI)   # virado para o jogador

		player.request_element(T.FIRE)
		player.request_weapon(Vector3(0, 0, -1))
		_check(is_equal_approx(500.0 - dummy.health.hp, 14.0 + 15.0), "adaga + Fogo: 14 + 15 (dano %d)" % (500 - dummy.health.hp))
		_check(player.weapon_charges == 2 and player.weapon_elements == [T.FIRE], "lâminas guardam o Fogo por mais 2 golpes")
		for i in 2:
			await _seconds(0.35)
			player.request_weapon(Vector3(0, 0, -1))
		_check(player.weapon_charges == 0 and player.weapon_elements.is_empty(), "depois de 3 golpes o Fogo acaba")

		_reset(dummy, Vector3(0, 0, -1.5), 0.0)   # de costas para o jogador
		await _seconds(0.35)
		player.request_weapon(Vector3(0, 0, -1))
		_check(is_equal_approx(500.0 - dummy.health.hp, 28.0), "pelas costas: 2x (dano %d)" % (500 - dummy.health.hp))

		await _seconds(0.35)
		player.request_ability(Vector3(0, 0, -1))
		await _seconds(0.2)
		_check(player.global_position.distance_to(Vector3(0, 0, -6)) < 0.3, "Passo sombrio avança 6 m (%s)" % player.global_position)
		_check(player.invisible > 0.0 and not dummy._is_valid_target(player), "invisível: inimigos ignoram")
		_check(player.ability_cooldown > 7.0, "Passo sombrio entra em recarga")

		_reset(dummy, player.global_position + Vector3(0, 0, -1.5), PI)   # de frente, mas saindo das sombras
		player.request_weapon(Vector3(0, 0, -1))
		_check(is_equal_approx(500.0 - dummy.health.hp, 28.0), "golpe saindo da invisibilidade: 2x")
		_check(player.invisible == 0.0, "atacar revela o Assassino")

	func _test_fighter() -> void:
		var T = E.Type
		_check(player.cls.label == "Lutador" and is_equal_approx(player.health.max_hp, 320.0), "Lutador: 320 de vida")
		player.health.damage(100.0)
		_check(is_equal_approx(player.health.hp, 245.0), "armadura: 100 de dano viram 75")
		player.health.reset()

		var dummy := await _spawn_dummy(Vector3(0, 0, -2.2), PI)
		player.request_weapon(Vector3(0, 0, -1))
		_check(is_equal_approx(500.0 - dummy.health.hp, 35.0), "golpe pesado: 35")

		_reset(dummy, Vector3(0, 0, -4), PI)
		dummy.set_physics_process(true)   # para receber o empurrão
		await _seconds(1.0)
		player.request_element(T.FIRE)
		player.request_ability(Vector3(0, 0, -1))
		await _seconds(0.6)
		_check(player.global_position.z < -1.5, "Investida avança (z=%.1f)" % player.global_position.z)
		_check(dummy.health.hp <= 500.0 - 30.0 - 15.0 and dummy.health.burning > 0.0, "Investida atropela com Fogo (hp=%d)" % dummy.health.hp)
		_check(player.queue_view.is_empty() and player.ability_cooldown > 0.0, "Investida consome a fila e entra em recarga")

	func _test_mage() -> void:
		_check(player.cls.label == "Mago" and is_equal_approx(player.health.max_hp, 200.0), "Mago: 200 de vida")
		var dummy := await _spawn_dummy(Vector3(0, 0, -2), PI)
		dummy.set_physics_process(true)
		player.request_ability(Vector3(0, 0, -1))
		await _seconds(0.4)
		_check(player.health.shielded > 3.0, "Escudo arcano protege")
		_check(dummy.global_position.z < -2.5, "Escudo arcano empurra (z=%.1f)" % dummy.global_position.z)

	# --- Ajudantes ---

	# Alvo: um lacaio parado (sem física: não anda, não vira, não ataca).
	func _spawn_dummy(at: Vector3, yaw: float) -> Node:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": at})
		await _seconds(0.2)
		var dummy: Node = get_tree().get_nodes_in_group("enemies").filter(
			func(e): return not e.is_queued_for_deletion())[0]
		dummy.info = dummy.info.duplicate()
		dummy.info.speed = 0.0
		dummy.info.damage = 0.0
		dummy.health.max_hp = 500.0
		_reset(dummy, at, yaw)
		return dummy

	func _reset(dummy: Node, at: Vector3, yaw: float) -> void:
		dummy.set_physics_process(false)
		dummy.health.reset()
		dummy.push_velocity = Vector3.ZERO
		dummy.global_position = at
		dummy.rotation = Vector3(0, yaw, 0)

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
