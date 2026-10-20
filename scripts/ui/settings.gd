# Tela de configurações: clique numa ação e aperte a nova tecla ou botão do mouse.
extends Control

const LOBBY_SCENE := "res://scenes/lobby.tscn"

var buttons := {}          # id da ação -> Button
var listening_id := ""     # ação esperando uma tecla nova
var hint_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := _label(column, "Configurações — Teclas", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for action in Keybinds.ACTIONS:
		var name_label := _label(grid, action.label, 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 34)
		button.pressed.connect(_start_listening.bind(action.id))
		grid.add_child(button)
		buttons[action.id] = button

	hint_label = _label(column, "", 16)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_button(row, "Restaurar padrão", _on_reset_pressed)
	_button(row, "Voltar", _on_back_pressed)

	_refresh()


func _refresh() -> void:
	for id in buttons:
		buttons[id].text = "Aperte uma tecla..." if id == listening_id else Keybinds.action_text(id)
	if listening_id.is_empty():
		hint_label.text = "Clique numa ação para trocar a tecla. Fixos: botão do meio para lançar em si mesmo, Esc para sair."
	else:
		hint_label.text = "Aperte a nova tecla ou botão do mouse (Esc cancela). Se ela já estiver em uso, as duas ações trocam."


func _start_listening(id: String) -> void:
	listening_id = id
	_refresh()


# _input vem antes da interface: assim o clique escolhido não aperta outro botão.
func _input(event: InputEvent) -> void:
	if listening_id.is_empty():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		listening_id = ""
		get_viewport().set_input_as_handled()
		_refresh()
		return
	var binding := Keybinds.event_to_binding(event)
	if binding.is_empty():
		return
	get_viewport().set_input_as_handled()
	Keybinds.set_binding(listening_id, binding)
	listening_id = ""
	_refresh()


func _on_reset_pressed() -> void:
	Keybinds.reset_defaults()
	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
