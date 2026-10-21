# Testes da lógica pura (carga, escolha de elementos, vida, ultimates, classes e teclas).
# Rodar: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const Health = preload("res://scripts/core/health.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")

var checks := 0
var failures := 0


func _init() -> void:
	_test_queue()
	_test_loadout()
	_test_health()
	_test_statuses()
	_test_skill_statuses()
	_test_ultimates()
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
	check(queue_of([T.SHIELD, T.SHIELD]) == [T.SHIELD, T.SHIELD], "repetir Escudo não anula")
	check(queue_of([T.WATER, T.FIRE]) == [T.STEAM], "Água + Fogo = Vapor")
	check(queue_of([T.COLD, T.WATER]) == [T.ICE], "Frio + Água = Gelo")
	check(queue_of([T.FIRE, T.FIRE, T.FIRE]) == [T.FIRE, T.FIRE, T.FIRE], "pode repetir o mesmo elemento")
	check(queue_of([T.FIRE, T.FIRE, T.FIRE, T.FIRE, T.FIRE]).size() == 3, "carga: no máximo 3")


func _test_loadout() -> void:
	var T = E.Type
	check(Loadout.is_valid([T.FIRE, T.LIGHTNING, T.ARCANE]), "Fogo, Raio e Arcano valem")
	check(not Loadout.is_valid([T.FIRE, T.EARTH, T.LIGHTNING]), "Terra e Raio são opostos")
	check(not Loadout.is_valid([T.FIRE, T.COLD, T.EARTH]), "Fogo e Frio são opostos")
	check(not Loadout.is_valid([T.FIRE, T.FIRE, T.EARTH]), "elementos repetidos não valem")
	check(not Loadout.is_valid([T.FIRE, T.EARTH]), "precisa de 3")
	check(not Loadout.is_valid([T.FIRE, T.EARTH, T.STEAM]), "só os 8 elementos básicos")
	check(Loadout.can_add([T.FIRE], T.EARTH) and not Loadout.can_add([T.FIRE], T.COLD), "lobby bloqueia o oposto")
	check(Loadout.is_valid([T.VOID, T.GRAVITY, T.SMOKE]), "Vazio, Gravidade e Fumaça juntos valem")
	check(not Loadout.is_valid([T.VOID, T.SHIELD, T.FIRE]), "Vazio e Escudo são opostos")
	check(not Loadout.is_valid([T.SMOKE, T.WATER, T.FIRE]), "Fumaça e Água são opostos")
	for id in Classes.ORDER:
		check(Loadout.is_valid(Loadout.default_for(id)), "padrão de %s é válido" % id)
	var all_valid := true
	for i in 30:
		all_valid = all_valid and Loadout.is_valid(Loadout.random())
	check(all_valid, "sorteio dos bots é sempre válido")
	check(Loadout.sanitize([T.FIRE, T.COLD, T.EARTH], "fighter") == Loadout.default_for("fighter"), "escolha inválida vira o padrão")
	check(Loadout.sanitize([7.0, 4.0, 5.0], "mage") == [T.FIRE, T.LIGHTNING, T.ARCANE], "números da rede viram elementos")


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
	check(keybinds.bindings.skill_q == ["key", KEY_Q] and keybinds.bindings.charge_1 == ["key", KEY_D],
		"skills no QWER, elementos no D F G")

	keybinds.set_binding("skill_q", ["key", KEY_E])
	check(keybinds.bindings.skill_q == ["key", KEY_E], "skill Q passa para o E")
	check(keybinds.bindings.skill_e == ["key", KEY_Q], "skill E (que usava o E) troca para o Q")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	check(event.is_action("skill_q") and not event.is_action("skill_e"), "InputMap atualizado")

	keybinds.set_binding("cast_weapon", ["mouse", MOUSE_BUTTON_RIGHT])
	check(keybinds.bindings.move_to_cursor == ["mouse", MOUSE_BUTTON_LEFT], "botões do mouse também trocam")
	check(Keybinds.event_to_binding(event) == ["key", KEY_E], "evento de tecla vira binding")

	keybinds.load_defaults()
	check(keybinds.bindings.charge_3 == ["key", KEY_G] and keybinds.bindings.move_to_cursor == ["mouse", MOUSE_BUTTON_RIGHT], "restaurar padrão (QWER, DFG, andar no botão direito)")
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


func _test_skill_statuses() -> void:
	var health := Health.new()
	health.max_hp = 100.0
	health.reset()
	health.slow(0.4, 2.0)
	check(is_equal_approx(health.speed_factor(), 0.6), "lento: -40% de velocidade")
	health.haste(0.3, 2.0)
	check(is_equal_approx(health.speed_factor(), 0.6 * 1.3), "acelerado soma com lento")
	health.stun(1.0)
	check(health.is_disabled() and health.speed_factor() == 0.0, "atordoado não anda")
	health.reset()
	health.make_vulnerable(0.3, 2.0)
	health.damage(10.0)
	check(is_equal_approx(health.hp, 87.0), "marcado leva +30% de dano")
	health.reset()
	health.fortify(0.3, 2.0)
	health.damage(10.0)
	check(is_equal_approx(health.hp, 93.0), "fortificado leva -30% de dano")
	# Novos elementos.
	var T = E.Type
	health.reset()
	health.shielded = 5.0
	health.set_ward([T.FIRE])
	health.haste(0.3, 5.0)
	health.apply_elements([T.VOID], 1.0)
	check(health.shielded == 0.0 and health.ward == 0.0 and health.hasted == 0.0 and is_equal_approx(health.hp, 75.0),
		"Vazio desfaz escudo, proteção e bônus (25 de dano)")
	health.reset()
	health.apply_elements([T.SMOKE], 1.0)
	check(health.blinded > 0.0, "Fumaça cega")
	health.apply_elements([T.WATER], 1.0)
	check(health.blinded == 0.0, "Água tira a fumaça")
	health.reset()
	health.apply_elements([T.GRAVITY], 1.0)
	check(health.slowed > 0.0 and is_equal_approx(health.speed_factor(), 0.7), "Gravidade deixa pesado (-30%)")
	health.immune_status = true
	health.reset()
	health.stun(1.0)
	health.slow(0.5, 1.0)
	check(not health.is_disabled() and health.speed_factor() == 1.0, "estruturas ignoram atordoar e lentidão")
	health.free()


func _test_ultimates() -> void:
	var T = E.Type
	check(Ultimates.resolve([T.FIRE]) == "meteor", "Fogo = Meteoro")
	check(Ultimates.resolve([T.EARTH, T.FIRE, T.EARTH]) == "quake", "dominante: Terra (2) vence Fogo (1)")
	check(Ultimates.resolve([T.FIRE, T.LIGHTNING]) == "meteor", "empate: vale o primeiro carregado")
	check(Ultimates.resolve([T.ICE]) == "frost" and Ultimates.resolve([T.STEAM]) == "tide", "Gelo = Inverno, Vapor = Maremoto")
	check(Ultimates.resolve([T.VOID]) == "eclipse" and Ultimates.resolve([T.GRAVITY, T.GRAVITY, T.SMOKE]) == "singularity"
		and Ultimates.resolve([T.SMOKE]) == "smokescreen", "Vazio = Eclipse, Gravidade = Singularidade, Fumaça = Cortina")
	check(Ultimates.resolve([]) == "", "sem carga não há ultimate")
	var all_mapped := true
	for element in Loadout.BASIC:
		all_mapped = all_mapped and Ultimates.ULTIMATES.has(Ultimates.resolve([element]))
	check(all_mapped, "todo elemento gera um ultimate")


func _test_classes() -> void:
	for id in Classes.ORDER:
		var info := Classes.info(id)
		var ok := true
		for key in ["label", "description", "hp", "speed", "armor", "mana", "mana_regen", "spell_power",
				"weapon", "backstab", "skills"]:
			ok = ok and info.has(key)
		for key in ["damage", "cooldown", "range", "angle", "push"]:
			ok = ok and info.weapon.has(key)
		for slot in Classes.SLOTS:
			var skill: Dictionary = info.skills.get(slot, {})
			for key in ["id", "label", "cost", "cooldown"]:
				ok = ok and skill.has(key)
			ok = ok and skill.get("cost", 999.0) <= info.mana
		check(ok, "classe %s tem atributos e as 4 skills" % id)
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
	check(is_equal_approx(base.max_mana, 160.0), "nível 1 = mana da classe")
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
