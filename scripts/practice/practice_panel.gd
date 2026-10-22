# Painel do modo Treino (lado esquerdo da tela; a tecla do painel mostra/esconde).
# Cada botão vira um pedido ao host (practice_state.gd), então funciona também
# com amigos na mesma partida de treino.
extends PanelContainer

const E = preload("res://scripts/core/elements.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Dummy = preload("res://scripts/practice/dummy.gd")
const PracticeState = preload("res://scripts/practice/practice_state.gd")

var state: Node                 # practice_state.gd
var player: Node                # personagem deste PC
var _options := {}              # id da opção -> CheckBox
var _class_buttons := {}        # id da classe -> Button
var _element_buttons := {}      # elemento -> Button
var _picked_class := Classes.DEFAULT
var _picked: Array = []
var _apply_button: Button
var _meter: Label
var _shown_player: Node
var _shown_class := ""


func _ready() -> void:
	position = Vector2(12, 128)
	custom_minimum_size.x = 320
	theme = Theme.new()
	theme.default_font_size = 13
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.82)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	_label(column, "Treino  (%s esconde)" % Keybinds.action_text("practice_panel"), 17)

	var checks := GridContainer.new()
	checks.columns = 2
	column.add_child(checks)
	for id in PracticeState.OPTIONS:
		var check := CheckBox.new()
		check.text = PracticeState.OPTIONS[id]
		check.focus_mode = Control.FOCUS_NONE
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(func(on): state.request_option.rpc_id(1, id, on))
		checks.add_child(check)
		_options[id] = check

	var row := _row(column)
	_button(row, "Zerar recargas", func(): state.request_action.rpc_id(1, "reset_cooldowns", ""))
	_button(row, "Encher vida/mana", func(): state.request_action.rpc_id(1, "refill", ""))
	row = _row(column)
	_button(row, "Limpar estados", func(): state.request_action.rpc_id(1, "clear_status", ""))
	_button(row, "Zerar medidor", func(): state.request_action.rpc_id(1, "reset_meter", ""))

	_label(column, "Bonecos", 15)
	row = _row(column)
	for kind in Dummy.ORDER:
		var short: String = Dummy.KINDS[kind].label.replace("Boneco ", "").replace("Boneco", "comum")
		_button(row, "+ " + short, func(): state.request_action.rpc_id(1, "add_dummy", kind))
	_button(row, "Tirar", func(): state.request_action.rpc_id(1, "clear_dummies", ""))
	_meter = _label(column, "", 13)

	_label(column, "Classe e elementos", 15)
	row = _row(column)
	for id in Classes.ORDER:
		var button := _button(row, Classes.info(id).label, _pick_class.bind(id))
		button.toggle_mode = true
		_class_buttons[id] = button
	var grid := GridContainer.new()
	grid.columns = 4
	column.add_child(grid)
	for element in Loadout.BASIC:
		var button := _button(grid, E.NAMES[element], _toggle_element.bind(element))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 12)
		_element_buttons[element] = button
	_apply_button = _button(column, "Trocar agora", _apply)


func _process(_delta: float) -> void:
	if not is_instance_valid(state):
		return
	for id in _options:
		_options[id].set_pressed_no_signal(state.get(id))
	# Personagem novo ou classe trocada: a escolha do painel passa a ser a dele.
	if is_instance_valid(player) and (player != _shown_player or player.class_id != _shown_class):
		_shown_player = player
		_shown_class = player.class_id
		_picked_class = player.class_id
		_picked = player.elements.duplicate()
		_refresh_choice()
	var total := 0.0
	var dps := 0.0
	for dummy in get_tree().get_nodes_in_group("dummies"):
		total += dummy.total_damage
		dps += dummy.dps
	_meter.text = "Dano nos bonecos: %d | DPS (5 s): %d" % [roundi(total), roundi(dps)]


func _pick_class(id: String) -> void:
	_picked_class = id
	_refresh_choice()


func _toggle_element(element: int) -> void:
	if element in _picked:
		_picked.erase(element)
	elif Loadout.can_add(_picked, element):
		_picked.append(element)
	_refresh_choice()


func _refresh_choice() -> void:
	for id in _class_buttons:
		_class_buttons[id].set_pressed_no_signal(id == _picked_class)
	for element in _element_buttons:
		var button: Button = _element_buttons[element]
		var chosen: bool = element in _picked
		button.set_pressed_no_signal(chosen)
		button.disabled = not chosen and not Loadout.can_add(_picked, element)
		button.modulate = E.COLORS[element].lightened(0.3) if chosen else Color.WHITE
	var problem := Loadout.problem(_picked)
	_apply_button.disabled = not problem.is_empty()
	_apply_button.text = "Trocar agora (D F G: %s)" % " ".join(_picked.map(func(element): return E.NAMES[element])) \
		if problem.is_empty() else problem


func _apply() -> void:
	if Loadout.is_valid(_picked):
		state.request_loadout.rpc_id(1, _picked_class, _picked)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	return row


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Control, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label
