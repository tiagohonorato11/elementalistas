# Teste do modo Treino em partida solo (sem janela):
#   godot --headless --path . res://tests/practice_smoke.tscn
# Bonecos (medidor de dano, vida de volta, renascer, revidar, andar), opções do
# painel (mana infinita, sem recarga, imortal) e troca de classe e elementos.
extends Node

const E = preload("res://scripts/core/elements.gd")


class Driver extends Node:
	var main: Node
	var state: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"
		Network.my_loadouts = {}
		Network.settings["mode"] = "practice"
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		await _seconds(0.3)
		await _test_dummies()
		await _test_options()
		await _test_loadout()
		print("treino: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		var scene := get_tree().current_scene
		if scene == null or scene.get("local_player") == null or scene.get("game_state") == null:
			return false
		main = scene
		state = main.game_state
		main.local_player.camera = null
		return true

	func player() -> Node:
		return main.local_player

	func _dummies() -> Array:
		return get_tree().get_nodes_in_group("dummies").filter(func(node): return not node.is_queued_for_deletion())

	func _of_kind(kind: String) -> Node:
		return _dummies().filter(func(node): return node.kind == kind)[0]

	func _test_dummies() -> void:
		var kinds := _dummies().map(func(node): return node.kind)
		_check(kinds.size() == 3 and "dummy" in kinds and "armored" in kinds and "fighter" in kinds,
			"começa com 3 bonecos: comum, blindado e que revida (%s)" % [kinds])
		_check(main.hud.practice_panel != null and main.hud.practice_panel.visible, "painel de treino aparece")

		# Medidor: Orbe no boneco comum.
		var dummy := _of_kind("dummy")
		player().global_position = Vector3.ZERO
		player().aim_point = dummy.global_position
		await _physics()
		player().request_skill("q", dummy.global_position, "")
		await _seconds(0.5)
		_check(is_equal_approx(dummy.total_damage, 30.0) and dummy.dps > 0.0,
			"medidor: dano %d, DPS %d" % [dummy.total_damage, dummy.dps])
		state.request_action("reset_meter", "")
		_check(dummy.total_damage == 0.0 and dummy.dps == 0.0, "zerar medidor")

		# Blindado: 40% de armadura.
		var armored := _of_kind("armored")
		armored.health.damage(100.0)
		_check(is_equal_approx(armored.health.max_hp - armored.health.hp, 60.0), "boneco blindado: 40% de armadura")

		# Vida e mana voltam depois de 4 s sem dano; cair e renascer.
		dummy.health.damage(300.0)
		dummy.mana = 10.0
		await _seconds(4.3)
		_check(dummy.health.hp == dummy.health.max_hp and dummy.mana == dummy.max_mana, "vida e mana voltam sem levar dano")
		dummy.health.damage(5000.0)
		_check(dummy.health.dead, "boneco cai")
		await _seconds(2.3)
		_check(not dummy.health.dead and dummy.health.hp == dummy.health.max_hp, "boneco renasce com vida cheia")

		# Vazio drena a mana do boneco.
		player().queue.add(E.Type.VOID)
		player().skill_cooldowns = {}
		player().request_skill("q", dummy.global_position, "")
		await _seconds(0.5)
		_check(dummy.mana < dummy.max_mana, "Vazio drena a mana do boneco (%d)" % dummy.mana)

		# Boneco que revida.
		var fighter := _of_kind("fighter")
		var hp: float = player().health.hp
		player().global_position = fighter.global_position + Vector3(0, 0, 1.5)
		await _seconds(1.7)
		_check(player().health.hp < hp, "boneco que revida bate em quem chega perto (%d -> %d)" % [hp, player().health.hp])
		player().global_position = Vector3.ZERO
		player().health.reset()

		# Bonecos andam.
		var start: Vector3 = dummy.global_position
		state.request_option("dummies_move", true)
		await _seconds(1.0)
		_check(dummy.global_position.distance_to(start) > 1.0, "bonecos andam (%.1f m)" % dummy.global_position.distance_to(start))
		state.request_option("dummies_move", false)

		# Pôr e tirar bonecos.
		state.request_action("add_dummy", "armored")
		await _seconds(0.2)
		_check(_dummies().size() == 4, "pôr boneco (%d)" % _dummies().size())
		state.request_action("clear_dummies", "")
		await _seconds(0.2)
		_check(_dummies().is_empty(), "tirar todos os bonecos")
		state.request_action("add_dummy", "dummy")
		await _seconds(0.2)

	func _test_options() -> void:
		var target: Vector3 = _dummies()[0].global_position
		state.request_option("infinite_mana", true)
		state.request_option("no_cooldowns", true)
		await _physics()
		player().request_skill("e", target, "")
		await _physics()
		await _physics()
		_check(player().mana == player().max_mana and player().skill_cooldowns.is_empty(), "mana infinita e sem recarga")
		player().request_skill("e", target, "")
		await _physics()
		_check(get_tree().current_scene.get_children().filter(func(node): return node.get("mini") == true).size() == 2,
			"sem recarga: dá para repetir a skill na hora")
		state.request_option("infinite_mana", false)
		state.request_option("no_cooldowns", false)

		state.request_option("immortal", true)
		await _physics()
		player().health.damage(5000.0)
		await _physics()
		_check(not player().health.dead and player().health.hp == player().health.max_hp, "imortal")
		state.request_option("immortal", false)
		await _physics()
		player().health.damage(5000.0)
		_check(player().health.dead, "sem imortal, cai")
		await _seconds(3.3)
		_check(not player().health.dead, "volta sozinho depois de cair")

		player().skill_cooldowns = {"q": 5.0}
		state.request_action("reset_cooldowns", "")
		_check(player().skill_cooldowns.is_empty(), "zerar recargas")
		player().mana = 0.0
		player().health.damage(50.0)
		state.request_action("refill", "")
		_check(player().mana == player().max_mana and player().health.hp == player().health.max_hp, "encher vida e mana")
		player().health.burning = 3.0
		state.request_action("clear_status", "")
		_check(player().health.burning == 0.0, "limpar estados")

	func _test_loadout() -> void:
		var T = E.Type
		var old: Node = player()
		var at: Vector3 = old.global_position
		state.request_loadout("assassin", [T.VOID, T.GRAVITY, T.BLOOD])
		await _seconds(0.2)
		_check(is_instance_valid(player()) and player() == old and player().class_id == "assassin"
			and player().elements == [T.VOID, T.GRAVITY, T.BLOOD] and player().global_position.distance_to(at) < 0.5,
			"trocar para Assassino com Vazio, Gravidade e Sangue no mesmo lugar")
		_check(is_equal_approx(player().health.max_hp, 140.0) and is_equal_approx(player().max_mana, 110.0)
			and player().unit_model.model_id == "assassin", "vida, mana e modelo do Assassino")
		state.request_loadout("fighter", [T.FIRE, T.COLD, T.EARTH])
		await _seconds(0.2)
		_check(player().class_id == "assassin", "escolha inválida (opostos) não troca")

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
