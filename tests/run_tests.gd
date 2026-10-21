# Testes da lógica pura (fila, resolvedor, vida, especiais e teclas).
# Rodar: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Health = preload("res://scripts/core/health.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")
const Specials = preload("res://scripts/core/specials.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")

var checks := 0
var failures := 0


func _init() -> void:
	_test_queue()
	_test_resolver()
	_test_health()
	_test_statuses()
	_test_specials()
	_test_keybinds()
	_test_classes()
	_test_moba()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FALHOU: " + message)


func queue_of(list: Array) -> Array:
	var queue := ElementQueue.new()
	for element in list:
		queue.add(element)
	return queue.elements


func _test_queue() -> void:
	var T = E.Type
	check(queue_of([T.WATER, T.LIGHTNING]) == [], "Água + Raio se anulam")
	check(queue_of([T.LIFE, T.ARCANE]) == [], "Vida + Arcano se anulam")
	check(queue_of([T.SHIELD, T.SHIELD]) == [], "Escudo + Escudo se anulam")
	check(queue_of([T.WATER, T.FIRE]) == [T.STEAM], "Água + Fogo = Vapor")
	check(queue_of([T.COLD, T.WATER]) == [T.ICE], "Frio + Água = Gelo")
	check(queue_of([T.WATER, T.FIRE, T.COLD]) == [], "Vapor + Frio se anulam")
	check(queue_of([T.FIRE, T.FIRE, T.COLD]) == [T.FIRE], "Frio anula só um Fogo")
	check(queue_of([T.LIFE, T.EARTH, T.ARCANE]) == [T.EARTH], "anulação remove o par certo")
	check(queue_of([T.FIRE, T.FIRE, T.FIRE, T.FIRE, T.FIRE, T.FIRE]).size() == 5, "limite de 5")


func _test_resolver() -> void:
	var T = E.Type
	var S = SpellResolver.Shape
	var cases := [
		[[], S.NONE],
		[[T.SHIELD, T.FIRE], S.BARRIER],
		[[T.EARTH, T.FIRE], S.PROJECTILE],
		[[T.ICE], S.PROJECTILE],
		[[T.ARCANE, T.FIRE], S.BEAM],
		[[T.LIFE], S.BEAM],
		[[T.LIGHTNING, T.FIRE], S.ARC],
		[[T.FIRE, T.FIRE], S.SPRAY],
		[[T.STEAM], S.SPRAY],
	]
	for test_case in cases:
		var got := SpellResolver.resolve_shape(test_case[0])
		check(got == test_case[1], "forma de %s: esperado %s, veio %s" % [test_case[0], test_case[1], got])


func _test_health() -> void:
	var T = E.Type
	var health := Health.new()
	health.max_hp = 100.0

	health.reset()
	health.apply_elements([T.LIGHTNING], 1.0)
	check(is_equal_approx(health.hp, 70.0), "Raio seco tira 30")

	health.reset()
	health.apply_elements([T.WATER], 1.0)
	health.apply_elements([T.LIGHTNING], 1.0)
	check(is_equal_approx(health.hp, 100.0 - 4.0 - 60.0), "Raio em alvo molhado dobra")

	health.reset()
	health.apply_elements([T.WATER], 1.0)
	health.apply_elements([T.FIRE], 1.0)
	check(health.wet == 0.0 and health.burning == 0.0, "Fogo seca em vez de incendiar")

	health.reset()
	health.apply_elements([T.FIRE], 1.0)
	check(health.burning > 0.0, "Fogo incendeia alvo seco")

	health.reset()
	health.apply_elements([T.EARTH], 1.0)
	health.apply_elements([T.LIFE, T.LIFE], 1.0)
	check(is_equal_approx(health.hp, 100.0), "Vida cura sem passar do máximo")

	health.reset()
	health.resistances = {T.FIRE: 0.0, T.COLD: 1.5}
	health.apply_elements([T.FIRE], 1.0)
	check(is_equal_approx(health.hp, 100.0) and health.burning == 0.0, "imune a Fogo não queima")
	health.apply_elements([T.COLD], 1.0)
	check(is_equal_approx(health.hp, 85.0), "fraqueza a Frio aumenta o dano")
	health.resistances = {}

	health.reset()
	health.damage(150.0)
	check(health.dead and health.hp == 0.0, "dano direto derruba")
	health.apply_elements([T.LIFE], 1.0)
	check(health.dead, "Vida não levanta quem não é revivível")
	health.revivable = true
	health.apply_elements([T.EARTH], 1.0)
	check(health.dead and health.hp == 0.0, "caído não recebe mais dano")
	health.apply_elements([T.LIFE], 1.0)
	check(not health.dead and is_equal_approx(health.hp, 50.0), "Vida revive com metade da vida")

	health.free()


func _test_keybinds() -> void:
	var keybinds := Keybinds.new()
	keybinds.persist = false
	keybinds.load_defaults()
	keybinds.apply_all()
	check(keybinds.bindings.element_water == ["key", KEY_Q], "Água começa no Q")

	keybinds.set_binding("element_water", ["key", KEY_E])
	check(keybinds.bindings.element_water == ["key", KEY_E], "Água passa para o E")
	check(keybinds.bindings.element_shield == ["key", KEY_Q], "Escudo (que usava o E) troca para o Q")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	check(event.is_action("element_water") and not event.is_action("element_shield"), "InputMap atualizado")

	keybinds.set_binding("cast_weapon", ["mouse", MOUSE_BUTTON_RIGHT])
	check(keybinds.bindings.move_to_cursor == ["mouse", MOUSE_BUTTON_LEFT], "botões do mouse também trocam")
	check(Keybinds.event_to_binding(event) == ["key", KEY_E], "evento de tecla vira binding")

	keybinds.load_defaults()
	check(keybinds.bindings.element_life == ["key", KEY_W] and keybinds.bindings.move_to_cursor == ["mouse", MOUSE_BUTTON_RIGHT], "restaurar padrão (QWER ASDF, andar no botão direito)")
	keybinds.free()


func _test_statuses() -> void:
	var T = E.Type
	var health := Health.new()
	health.max_hp = 200.0

	health.reset()
	health.apply_elements([T.WATER], 1.0)
	health.apply_elements([T.COLD], 1.0)
	check(health.frozen > 0.0 and health.wet == 0.0, "Frio em alvo molhado congela")
	health.apply_elements([T.FIRE], 1.0)
	check(health.frozen == 0.0 and health.burning == 0.0, "Fogo descongela sem incendiar")

	health.reset()
	health.freeze(2.0)
	var before := health.hp
	health.apply_elements([T.EARTH], 1.0)
	check(is_equal_approx(before - health.hp, 80.0) and health.frozen == 0.0, "Terra estilhaça congelado (2x)")

	health.reset()
	health.set_ward([T.FIRE, T.LIGHTNING])
	health.apply_elements([T.FIRE, T.LIGHTNING], 1.0)
	check(is_equal_approx(health.hp, 200.0) and health.burning == 0.0, "proteção bloqueia os elementos dela")
	health.apply_elements([T.ARCANE], 1.0)
	check(is_equal_approx(health.hp, 165.0), "proteção não bloqueia outros elementos")
	health.free()


func _test_specials() -> void:
	var T = E.Type
	check(Specials.match_special([T.FIRE, T.EARTH, T.FIRE, T.EARTH]) == "meteor", "receita do Meteoro")
	check(Specials.match_special([T.EARTH, T.EARTH, T.FIRE, T.FIRE]) == "meteor", "ordem não importa")
	check(Specials.match_special([T.FIRE, T.EARTH, T.FIRE]) == "", "receita incompleta não lança")
	check(Specials.match_special([]) == "", "fila vazia não lança")
	# Toda receita precisa sobreviver às anulações e fusões da fila.
	for id in Specials.ORDER:
		var recipe: Array = Specials.SPECIALS[id].recipe
		check(Specials.match_special(queue_of(recipe)) == id, "receita de %s é montável na fila" % id)


func _test_classes() -> void:
	for id in Classes.ORDER:
		var info := Classes.info(id)
		var ok := true
		for key in ["label", "description", "hp", "speed", "armor", "spell_power", "special_cooldown",
				"weapon", "backstab", "ability", "ability_label", "ability_cooldown"]:
			ok = ok and info.has(key)
		for key in ["damage", "cooldown", "range", "angle", "push", "element_scale", "charges"]:
			ok = ok and info.weapon.has(key)
		check(ok, "classe %s tem todos os atributos" % id)
	check(Classes.info("nao_existe").label == "Mago", "classe desconhecida vira Mago")

	var health := Health.new()
	health.max_hp = 100.0
	health.armor = 0.25
	health.reset()
	health.damage(40.0)
	check(is_equal_approx(health.hp, 70.0), "armadura de 25% reduz o dano")
	health.shielded = 1.0
	health.damage(40.0)
	check(is_equal_approx(health.hp, 55.0), "armadura e escudo se somam")
	health.free()


class Unit extends RefCounted:
	var team: int
	func _init(p_team: int) -> void:
		team = p_team


func _test_moba() -> void:
	var T = E.Type
	# Times: no MOBA aliados só recebem a Vida.
	var ally := Unit.new(Combat.BLUE)
	var enemy := Unit.new(Combat.RED)
	Combat.friendly_fire = false
	check(Combat.filter_elements(Combat.BLUE, ally, [T.FIRE, T.LIFE]) == [T.LIFE], "MOBA: aliado só recebe a Vida")
	check(Combat.filter_elements(Combat.BLUE, enemy, [T.FIRE, T.LIFE]) == [T.FIRE, T.LIFE], "MOBA: inimigo recebe tudo")
	check(not Combat.can_harm(Combat.BLUE, ally) and Combat.can_harm(Combat.BLUE, enemy), "MOBA: sem fogo amigo")
	Combat.friendly_fire = true
	check(Combat.can_harm(Combat.BLUE, ally), "Arena: fogo amigo ligado")

	# Níveis e atributos.
	check(Progression.apply_xp(1, 0, Progression.xp_to_next(1)) == [2, 0], "xp suficiente sobe de nível")
	check(Progression.apply_xp(Progression.MAX_LEVEL, 0, 99999)[0] == Progression.MAX_LEVEL, "nível máximo")
	var mage := Classes.info("mage")
	var base := Progression.stats(mage, 1, [], {})
	check(is_equal_approx(base.max_hp, 200.0) and is_equal_approx(base.power, 1.0), "nível 1 = atributos da classe")
	var strong := Progression.stats(mage, 3, ["amuleto", "foco"], {"golem": 10.0})
	check(is_equal_approx(strong.max_hp, 200.0 * 1.16 + 90.0), "vida: nível + Amuleto")
	check(is_equal_approx(strong.power, 1.12 * (1.0 + 0.12 + 0.2)), "dano: nível x (Foco + Fúria do Golem)")
	check(Progression.cannot_buy("amuleto", 100, [], true) == "ouro insuficiente", "loja: sem ouro")
	check(Progression.cannot_buy("amuleto", 999, [], false) != "", "loja: só na fonte")
	check(Progression.cannot_buy("amuleto", 999, [], true) == "", "loja: pode comprar")

	# Mapa: 16 estruturas, dependências válidas e acampamentos espelhados.
	var structures := MobaMap.structures()
	var ids := structures.map(func(s): return s.id)
	var valid := true
	for s in structures:
		for required in s.requires:
			valid = valid and required in ids
	check(structures.size() == 16 and valid, "mapa: 16 estruturas com dependências válidas")
	var camps := MobaMap.camps()
	check(camps.size() == 5 and camps[0].pos == -camps[1].pos, "mapa: 4 acampamentos espelhados + Guardião")
	var blue_path := MobaMap.lane_path(Combat.BLUE, "norte")
	var red_path := MobaMap.lane_path(Combat.RED, "norte")
	check(blue_path[0].x < 0 and red_path[0].x > 0 and blue_path.back().x > 0, "rotas vão de uma base à outra")
