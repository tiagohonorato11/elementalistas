# Teste do modo MOBA em partida solo (você + 5 bots), sem janela:
#   godot --headless --path . res://tests/moba_smoke.tscn
# Confere montagem, tropas, bots, loja, morte/reaparecer, selva, Guardião e a
# ordem de destruição até a vitória. Termina com código 0 se tudo passar.
extends Node

const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const Progression = preload("res://scripts/moba/progression.gd")


class Driver extends Node:
	var main: Node
	var state: Node
	var player: Node
	var failures := 0

	func _ready() -> void:
		Network.my_class = "mage"
		Network.settings = {"mode": "moba", "bots": true}
		var started := Time.get_ticks_msec()
		Network.host()
		Network.start_game()
		await _wait_until(func(): return _scene_ready())
		print("mapa pronto em %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
		await _seconds(0.5)
		await _run()
		print("moba: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	func _scene_ready() -> bool:
		main = get_tree().current_scene
		if main == null or main.get("local_player") == null or main.get("game_state") == null:
			return false
		state = main.game_state
		player = main.local_player
		player.camera = null
		return true

	func _run() -> void:
		# 1) Montagem.
		var structures := get_tree().get_nodes_in_group("structures")
		_check(structures.size() == 16, "16 estruturas (%d)" % structures.size())
		var champions: Array = state.champions()
		var blue := champions.filter(func(c): return c.team == Combat.BLUE).size()
		_check(champions.size() == 6 and blue == 3, "6 campeões, 3 por time (%d, azul %d)" % [champions.size(), blue])
		_check(champions.filter(func(c): return c.is_bot).size() == 5, "5 bots")
		_check(get_tree().get_nodes_in_group("enemies").size() == 7, "selva: 7 monstros")
		var outer: Node = main.get_node("vermelho_norte_torre_externa")
		var inner: Node = main.get_node("vermelho_norte_torre_interna")
		_check(not outer.health.invulnerable and inner.health.invulnerable, "torre interna protegida até a externa cair")
		_check(player.team == Combat.BLUE and player.global_position.distance_to(MobaMap.fountain(Combat.BLUE)) < 4.0, "você começa na fonte azul")

		# 2) Partida acelerada: tropas e bots.
		Engine.time_scale = 3.0
		await _seconds(17.0)
		_check(get_tree().get_nodes_in_group("minions").size() >= 18, "primeira leva de tropas (%d)" % get_tree().get_nodes_in_group("minions").size())
		await _seconds(40.0)
		Engine.time_scale = 1.0
		var bots: Array = state.champions().filter(func(c): return c.is_bot)
		var advanced := bots.filter(func(b): return absf(b.global_position.x) < 45.0).size()
		_check(advanced >= 3, "bots saíram da base para as rotas (%d de 5)" % advanced)
		var earned := bots.filter(func(b): return b.gold > Progression.START_GOLD + 150 or b.level > 1).size()
		_check(earned >= 1, "bots ganharam ouro/xp lutando (%s)" % [bots.map(func(b): return "%s nv%d %dg" % [b.cls.label, b.level, b.gold])])
		var damaged := get_tree().get_nodes_in_group("structures").filter(func(s): return s.health.hp < s.health.max_hp).size()
		print("info: estruturas danificadas=%d, tropas=%d" % [damaged, get_tree().get_nodes_in_group("minions").size()])

		# 3) Loja na fonte.
		var hp_before: float = player.health.max_hp
		player.gold = 1000
		player.request_buy("amuleto")
		_check(player.items == ["amuleto"] and is_equal_approx(player.health.max_hp, hp_before + 90.0), "comprar Amuleto na fonte (+90 de vida)")
		player.global_position = Vector3(0, 0, 24)
		await _seconds(0.1)
		player.request_buy("botas")
		_check(player.items.size() == 1, "longe da fonte não compra")

		# 4) Morte e reaparecer.
		player.health.damage(99999.0)
		_check(player.health.dead and player.respawn_time > 0.0, "caiu: espera para reaparecer (%.1f s)" % player.respawn_time)
		await _seconds(player.respawn_time + 0.5)
		_check(not player.health.dead and player.global_position.distance_to(MobaMap.fountain(Combat.BLUE)) < 4.0,
			"reapareceu na fonte com vida cheia (%d/%d)" % [player.health.hp, player.health.max_hp])

		# 5) Selva: provocar o Golem azul e derrotá-lo dá ouro e o bônus.
		var golem: Node = _monster("jungle_golem", Vector3(-16, 0, -8))
		player.global_position = golem.camp_position + Vector3(0, 0, 3)
		await _seconds(0.2)
		golem.health.damage(10.0)
		await _seconds(1.0)
		_check(golem.aggressive and golem.target == player, "Golem provocado ataca quem está perto")
		var gold_before: int = player.gold
		golem.health.damage(99999.0)
		await _seconds(0.1)
		_check(player.buffs.has("golem") and player.gold > gold_before, "derrotar o Golem dá ouro e a Fúria do Golem")
		_check(player.power > 1.0, "bônus aumenta o dano (x%.2f)" % player.power)

		# 6) Guardião: bônus para o time inteiro.
		var boss: Node = _monster("boss", Vector3.ZERO)
		player.global_position = Vector3(0, 0, 4)
		await _seconds(0.2)
		boss.health.damage(99999.0)
		await _seconds(0.1)
		var blessed: int = state.champions().filter(func(c): return c.team == Combat.BLUE and c.buffs.has("guardiao")).size()
		_check(blessed == 3, "Guardião abençoa os 3 do time azul (%d)" % blessed)
		_check(state.boss_timer > 0.0, "Guardião renasce depois")

		# 7) Ordem de destruição até a vitória do Azul.
		player.global_position = MobaMap.fountain(Combat.BLUE)
		for id in ["vermelho_norte_torre_externa", "vermelho_norte_torre_interna"]:
			main.get_node(id).health.damage(99999.0)
		var inhibitor: Node = main.get_node("vermelho_norte_inibidor")
		_check(not inhibitor.health.invulnerable, "inibidor abre depois das duas torres")
		var nexus_tower: Node = main.get_node("vermelho_torre_nexus")
		_check(nexus_tower.health.invulnerable, "torre do nexus protegida enquanto os inibidores estão de pé")
		inhibitor.health.damage(99999.0)
		_check(not nexus_tower.health.invulnerable, "inibidor caído abre a torre do nexus")
		var nexus: Node = main.get_node("vermelho_nexus")
		_check(nexus.health.invulnerable, "nexus protegido pela torre do nexus")
		state.wave_timer = 0.05
		await _seconds(0.3)
		var supers := get_tree().get_nodes_in_group("minions").filter(func(m): return m.kind == "super" and m.team == Combat.BLUE).size()
		_check(supers == 1, "inibidor vermelho caído: supertropa azul na rota norte (%d)" % supers)
		nexus_tower.health.damage(99999.0)
		nexus.health.damage(99999.0)
		await _seconds(0.1)
		_check(state.is_over() and state.winner == Combat.BLUE, "nexus vermelho destruído: vitória do Azul")

	# --- Ajudantes ---

	func _monster(kind: String, camp: Vector3) -> Node:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.kind == kind and enemy.camp_position.distance_to(camp) < 1.0:
				return enemy
		return null

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
