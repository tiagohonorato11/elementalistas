# Testes da lógica pura (fila, resolvedor e vida).
# Rodar: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Health = preload("res://scripts/core/health.gd")
const Keybinds = preload("res://scripts/ui/keybinds.gd")

var checks := 0
var failures := 0


func _init() -> void:
	_test_queue()
	_test_resolver()
	_test_health()
	_test_keybinds()
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
	check(keybinds.bindings.element_life == ["key", KEY_Q], "Vida (que usava o E) troca para o Q")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	check(event.is_action("element_water") and not event.is_action("element_life"), "InputMap atualizado")

	keybinds.set_binding("cast_forward", ["mouse", MOUSE_BUTTON_LEFT])
	check(keybinds.bindings.move_to_cursor == ["mouse", MOUSE_BUTTON_RIGHT], "botões do mouse também trocam")
	check(Keybinds.event_to_binding(event) == ["key", KEY_E], "evento de tecla vira binding")

	keybinds.load_defaults()
	check(keybinds.bindings.element_life == ["key", KEY_E], "restaurar padrão")
	keybinds.free()
