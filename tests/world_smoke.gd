# Teste do modo Mundo (RPG) em partida solo (sem janela):
#   godot --headless --path . res://tests/world_smoke.tscn
# Mapa e acampamentos, fonte da vila, missão (aceitar, contar, entregar),
# monstros que atacam quem chega perto, recompensas, loja do Ferreiro,
# acampamento renascendo e voltar à vila depois de cair.
extends Node

const WorldMap = preload("res://scripts/world/world_map.gd")
const Quests = preload("res://scripts/world/quests.gd")
const Enemy = preload("res://scripts/gameplay/enemy.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var state: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"
		Network.my_loadouts = {}
		Network.settings["mode"] = "world"
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		await _seconds(0.5)
		await _test_world()
		await _test_quest()
		await _test_shop_and_respawn()
		print("mundo: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		var scene := get_tree().current_scene
		if scene == null or scene.get("local_player") == null or scene.get("game_state") == null:
			return false
		main = scene
		player = main.local_player
		state = main.game_state
		player.camera = null
		return true

	func _monsters(kind := "") -> Array:
		return get_tree().get_nodes_in_group("enemies").filter(func(node):
			return not node.is_queued_for_deletion() and not node.health.dead and (kind.is_empty() or node.kind == kind))

	func _move(at: Vector3) -> void:
		player.global_position = at
		player.has_move_target = false

	func _test_world() -> void:
		var total := 0
		var kinds_ok := true
		for camp in WorldMap.CAMPS:
			total += camp.kinds.size()
			for kind in camp.kinds:
				kinds_ok = kinds_ok and Enemy.KINDS.has(kind)
		_check(kinds_ok, "todo monstro do mapa existe")
		_check(_monsters().size() == total, "acampamentos: %d monstros (%d)" % [total, _monsters().size()])
		var npcs := main.get_children().filter(func(node): return node.get("role") != null)
		_check(npcs.size() == 2, "Anciã e Ferreiro na vila")
		_check(WorldMap.zone_at(player.global_position) == "Vila" and player.progression and player.world, "começa na vila")
		player.health.damage(80.0)
		var hp: float = player.health.hp
		_move(WorldMap.FOUNTAIN + Vector3(1, 0, 0))
		await _seconds(1.0)
		_check(player.health.hp > hp + 20.0, "a fonte da vila cura (%d -> %d)" % [hp, player.health.hp])

	func _test_quest() -> void:
		_move(WorldMap.ELDER + Vector3(0, 0, 1.5))
		await _seconds(0.2)
		var hud: Node = main.hud
		_check(hud.dialog_panel != null and hud.dialog_panel.visible and "Aceitar" in hud._dialog_button.text,
			"perto da Anciã: conversa com a missão")
		player.request_quest("accept")
		_check(Quests.active(player.quests) == "carnicais", "missão aceita")

		# Chegar perto de um Carniçal faz o acampamento atacar.
		var ghoul: Node = _monsters("ghoul")[0]
		_move(ghoul.global_position + Vector3(4.5, 0, 0))
		await _seconds(0.8)
		_check(ghoul.aggressive, "Carniçal ataca quem chega perto")

		var gold: int = player.gold
		var xp_before: int = player.xp + player.level * 1000
		for i in 5:
			var target: Node = _monsters("ghoul")[0]
			_move(target.global_position + Vector3(2, 0, 0))
			target.health.damage(99999.0)
			await _seconds(0.1)
		_check(player.gold >= gold + 5 * 12, "monstros dão ouro (%d -> %d)" % [gold, player.gold])
		_check(player.xp + player.level * 1000 > xp_before, "monstros dão xp")
		_check(Quests.is_complete(player.quests, "carnicais"), "missão: 5 Carniçais (%s)" % Quests.tracker(player.quests))

		player.request_quest("turn_in")
		_check(not player.quests.carnicais.done, "longe da Anciã não entrega")
		_move(WorldMap.ELDER + Vector3(0, 0, 1.5))
		player.health.reset()
		gold = player.gold
		player.request_quest("turn_in")
		_check(player.quests.carnicais.done and player.gold == gold + 120, "entregar dá a recompensa (+120)")
		_check(Quests.next_offer(player.quests) == "ossos", "próxima missão: Ossos inquietos")

		# Acampamento vazio renasce.
		var emptied := ""
		for camp in WorldMap.CAMPS:
			if state.respawn_left(camp.id) > 0.0:
				emptied = camp.id
		_check(not emptied.is_empty(), "acampamento vazio espera para renascer (%s)" % emptied)
		state._camp_timers[emptied] = 0.1
		await _seconds(0.4)
		_check(state.respawn_left(emptied) == 0.0 and _monsters("ghoul").size() >= 4, "acampamento renasce")

	func _test_shop_and_respawn() -> void:
		_move(Vector3(0, 0, 0))
		player.gold = 500
		player.request_buy("botas")
		_check(player.items.is_empty(), "longe do Ferreiro não compra")
		_move(WorldMap.MERCHANT + Vector3(0, 0, 1.5))
		player.request_buy("botas")
		_check(player.items == ["botas"] and player.gold == 250, "compra no Ferreiro")

		_move(Vector3(0, 0, 0))
		player.health.damage(99999.0)
		_check(player.health.dead and player.respawn_time > 0.0, "caiu: espera para voltar")
		player.respawn_time = 0.1
		await _seconds(0.5)
		_check(not player.health.dead and player.global_position.distance_to(WorldMap.FOUNTAIN) < 9.0,
			"volta na vila com vida cheia")

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
