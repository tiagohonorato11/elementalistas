# Teclas configuráveis (autoload "Keybinds"). Cada ação tem uma tecla ou botão do
# mouse, aplicada no InputMap do Godot e salva em user://settings.cfg.
# Fixos (não configuráveis): setas para andar, botão do meio = em si mesmo, Esc e R.
extends Node

const SAVE_PATH := "user://settings.cfg"
const SECTION := "teclas"
# Ao mudar os padrões de forma incompatível, aumente: configurações antigas são descartadas.
const SETTINGS_VERSION := 2

const ACTIONS := [
	{"id": "move_up", "label": "Andar para cima", "default": ["key", KEY_W]},
	{"id": "move_down", "label": "Andar para baixo", "default": ["key", KEY_S]},
	{"id": "move_left", "label": "Andar para a esquerda", "default": ["key", KEY_A]},
	{"id": "move_right", "label": "Andar para a direita", "default": ["key", KEY_D]},
	{"id": "move_to_cursor", "label": "Andar até o cursor (segurar)", "default": ["mouse", MOUSE_BUTTON_XBUTTON1]},
	{"id": "element_water", "label": "Água", "default": ["key", KEY_Q]},
	{"id": "element_life", "label": "Vida", "default": ["key", KEY_E]},
	{"id": "element_shield", "label": "Escudo", "default": ["key", KEY_R]},
	{"id": "element_cold", "label": "Frio", "default": ["key", KEY_F]},
	{"id": "element_lightning", "label": "Raio", "default": ["key", KEY_Z]},
	{"id": "element_arcane", "label": "Arcano", "default": ["key", KEY_X]},
	{"id": "element_earth", "label": "Terra", "default": ["key", KEY_C]},
	{"id": "element_fire", "label": "Fogo", "default": ["key", KEY_V]},
	{"id": "cast_forward", "label": "Lançar à frente", "default": ["mouse", MOUSE_BUTTON_RIGHT]},
	{"id": "area_modifier", "label": "Modificador de área (segurar ao lançar)", "default": ["key", KEY_SHIFT]},
	{"id": "cast_self", "label": "Lançar em si mesmo", "default": ["key", KEY_SPACE]},
	{"id": "cast_weapon", "label": "Golpe com a arma", "default": ["mouse", MOUSE_BUTTON_LEFT]},
	{"id": "cast_special", "label": "Feitiço especial (receita na fila)", "default": ["key", KEY_G]},
	{"id": "class_ability", "label": "Habilidade da classe", "default": ["key", KEY_CTRL]},
]

const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Botão esquerdo",
	MOUSE_BUTTON_RIGHT: "Botão direito",
	MOUSE_BUTTON_MIDDLE: "Botão do meio",
	MOUSE_BUTTON_XBUTTON1: "Botão lateral 1",
	MOUSE_BUTTON_XBUTTON2: "Botão lateral 2",
	MOUSE_BUTTON_WHEEL_UP: "Rodinha para cima",
	MOUSE_BUTTON_WHEEL_DOWN: "Rodinha para baixo",
}

var bindings := {}       # id -> ["key" | "mouse", código]
var persist := true      # os testes desligam para não gravar arquivo


func _ready() -> void:
	load_defaults()
	_load()
	apply_all()


func load_defaults() -> void:
	for action in ACTIONS:
		bindings[action.id] = action.default.duplicate()


func reset_defaults() -> void:
	load_defaults()
	apply_all()
	save()


# Troca de lugar com a ação que já usava essa tecla, para não haver conflito.
func set_binding(id: String, binding: Array) -> void:
	var previous: Array = bindings[id]
	for other in bindings:
		if other != id and bindings[other] == binding:
			bindings[other] = previous
			_apply(other)
	bindings[id] = binding
	_apply(id)
	save()


func apply_all() -> void:
	for action in ACTIONS:
		_apply(action.id)


func _apply(id: String) -> void:
	if not InputMap.has_action(id):
		InputMap.add_action(id)
	InputMap.action_erase_events(id)
	InputMap.action_add_event(id, _make_event(bindings[id]))


static func _make_event(binding: Array) -> InputEvent:
	if binding[0] == "mouse":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = binding[1]
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = binding[1]
	return key


# Converte um aperto de tecla/botão em binding; vazio se não servir.
static func event_to_binding(event: InputEvent) -> Array:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return ["key", code]
	if event is InputEventMouseButton and event.pressed:
		return ["mouse", event.button_index]
	return []


static func binding_text(binding: Array) -> String:
	if binding[0] == "mouse":
		return MOUSE_NAMES.get(binding[1], "Botão %d" % binding[1])
	# Mostra o nome conforme o layout do teclado do jogador (sem janela não há layout).
	var keycode: int = binding[1]
	if DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_keycode_from_physical(keycode)
		if mapped != KEY_NONE:
			keycode = mapped
	return OS.get_keycode_string(keycode)


func action_text(id: String) -> String:
	return binding_text(bindings[id])


func save() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("geral", "versao", SETTINGS_VERSION)
	for id in bindings:
		config.set_value(SECTION, id, "%s:%d" % bindings[id])
	config.save(SAVE_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or config.get_value("geral", "versao", 1) != SETTINGS_VERSION:
		return
	for id in bindings:
		var parts := String(config.get_value(SECTION, id, "")).split(":")
		if parts.size() == 2 and (parts[0] == "key" or parts[0] == "mouse") and parts[1].is_valid_int():
			bindings[id] = [parts[0], parts[1].to_int()]
