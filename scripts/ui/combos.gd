# Grimório de combos: escolha uma classe e 3 elementos e veja todas as cargas
# que dá para montar com D F G e o que cada skill (Q W E R) faz com elas, com
# uma prévia animada. "Usar no lobby" leva a escolha para a partida.
extends Control

const Classes = preload("res://scripts/core/classes.gd")
const E = preload("res://scripts/core/elements.gd")
const ElementInfo = preload("res://scripts/core/element_info.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Glyphs = preload("res://scripts/ui/glyphs.gd")
const SkillIcon = preload("res://scripts/ui/skill_icon.gd")
const SkillPreview = preload("res://scripts/ui/skill_preview.gd")
const SkillText = preload("res://scripts/ui/skill_text.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const CHARGE_ACTIONS := ["charge_1", "charge_2", "charge_3"]
const SKILL_ACTIONS := {"q": "skill_q", "w": "skill_w", "e": "skill_e", "r": "skill_r"}
const PANEL := Color(0.15, 0.15, 0.2)
const GOLD := Color(1.0, 0.8, 0.25)
# Máximos dos atributos entre as classes, para as barras.
const STAT_BARS := [["hp", "Vida", 320.0], ["mana", "Mana", 160.0], ["speed", "Velocidade", 6.5],
	["armor", "Armadura", 0.25]]

var class_id := Classes.DEFAULT
var picking: Array = []        # elementos marcados (vale com 3)
var combos: Array = []         # Loadout.charges(picking)
var combo_index := 0
var slot := "q"

var class_buttons := {}
var stats_box: VBoxContainer
var element_buttons := {}      # elemento -> Button
var keys_label: Label
var combo_list: VBoxContainer
var combo_title: Label
var combo_slots: Array = []    # 3 SkillIcon "slot" do cabeçalho
var combo_effects: Label
var preview: Control
var skill_cards := {}          # slot -> PanelContainer
var skill_icons := {}          # slot -> SkillIcon
var description: RichTextLabel
var use_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	class_id = Network.my_class
	picking = Network.my_elements()
	_build_ui()
	_refresh_class()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# Cabeçalho.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)
	_label(header, "Grimório de combos", 30)
	var hint := _label(header, "Escolha a classe e 3 elementos; clique numa carga e numa skill para ver a prévia.", 14)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9))
	use_button = _button(header, "Usar no lobby", _use)
	use_button.custom_minimum_size.x = 140
	_button(header, "Voltar", _back).custom_minimum_size.x = 100

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	page.add_child(body)
	_build_loadout_column(body)
	_build_combo_column(body)
	_build_preview_column(body)


# Coluna 1: classe, atributos e elementos.
func _build_loadout_column(parent: Node) -> void:
	var column := _panel(parent, 290)
	_label(column, "Classe", 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	for id in Classes.ORDER:
		var button := _button(row, Classes.info(id).label, _on_class_pressed.bind(id))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		class_buttons[id] = button
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 3)
	column.add_child(stats_box)

	_label(column, "Elementos (opostos se anulam)", 18)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for element in Loadout.BASIC:
		var button := _button(grid, "         " + E.NAMES[element], _on_element_pressed.bind(element))
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_pressed_color", Color.BLACK)
		button.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
		var style := StyleBoxFlat.new()
		style.bg_color = E.COLORS[element]
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_stylebox_override("hover_pressed", style)
		button.tooltip_text = "%s: %s" % [E.NAMES[element], ElementInfo.EFFECTS[element]]
		var dot := _icon(button, "slot", Vector2(24, 24))
		dot.position = Vector2(6, 5)
		dot.set_view({"glyph": Glyphs.element_id(element), "glyph_color": E.COLORS[element]})
		element_buttons[element] = button
	keys_label = _label(column, "", 14)
	keys_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rules := _label(column, "Na carga: Água + Fogo = Vapor, Água + Frio = Gelo. No ultimate vale o elemento "
		+ "que mais aparece (no empate, o 1º apertado); 3 iguais = MEGA.", 12)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82))


# Coluna 2: todas as cargas possíveis.
func _build_combo_column(parent: Node) -> void:
	var column := _panel(parent, 300)
	_label(column, "Cargas possíveis", 18)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	combo_list = VBoxContainer.new()
	combo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combo_list.add_theme_constant_override("separation", 4)
	scroll.add_child(combo_list)


# Coluna 3: carga escolhida, prévia animada, skills e texto.
func _build_preview_column(parent: Node) -> void:
	var column := _panel(parent, 0)
	column.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	column.add_child(head)
	for i in 3:
		combo_slots.append(_icon(head, "slot", Vector2(30, 30)))
	combo_title = _label(head, "", 20)
	combo_effects = _label(column, "", 13)
	combo_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combo_effects.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))

	preview = SkillPreview.new()
	preview.clip_contents = true
	preview.custom_minimum_size = Vector2(0, 230)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	column.add_child(cards)
	for id in Classes.SLOTS:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_input.bind(id))
		cards.add_child(card)
		var icon := _icon(card, "skill", Vector2(110, 84))
		skill_cards[id] = card
		skill_icons[id] = icon

	description = RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.custom_minimum_size = Vector2(0, 110)
	description.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(description)


# --- Escolhas ---

func _on_class_pressed(id: String) -> void:
	class_id = id
	picking = Loadout.sanitize(Network.my_loadouts.get(id, []), id)
	_refresh_class()


func _on_element_pressed(element: int) -> void:
	if element in picking:
		picking.erase(element)
	elif Loadout.can_add(picking, element):
		picking.append(element)
	_refresh_elements()


func _on_combo_pressed(index: int) -> void:
	combo_index = index
	_refresh_combo()


func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_slot(id)


func select_slot(id: String) -> void:
	slot = id
	_refresh_combo()


func _use() -> void:
	if not Loadout.is_valid(picking):
		return
	Network.set_my_class(class_id)
	Network.set_my_elements(picking)
	_back()


func _back() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


# --- Atualização ---

func _refresh_class() -> void:
	for id in class_buttons:
		class_buttons[id].set_pressed_no_signal(id == class_id)
	for child in stats_box.get_children():
		child.queue_free()
	var info := Classes.info(class_id)
	for entry in STAT_BARS:
		var row := HBoxContainer.new()
		stats_box.add_child(row)
		var name_label := _label(row, entry[1], 13)
		name_label.custom_minimum_size.x = 82
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = entry[2]
		bar.value = info[entry[0]]
		bar.custom_minimum_size = Vector2(120, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var value: float = info[entry[0]]
		_label(row, ("%d%%" % roundi(value * 100.0)) if entry[0] == "armor" else str(roundi(value)), 13) \
			.custom_minimum_size.x = 38
	_refresh_elements()


func _refresh_elements() -> void:
	for element in element_buttons:
		var chosen: bool = element in picking
		element_buttons[element].set_pressed_no_signal(chosen)
		element_buttons[element].disabled = not chosen and not Loadout.can_add(picking, element)
	use_button.disabled = not Loadout.is_valid(picking)
	if picking.size() < Loadout.SIZE:
		keys_label.text = "Escolha mais %d elemento(s)." % (Loadout.SIZE - picking.size())
	else:
		var keys := PackedStringArray()
		for i in picking.size():
			keys.append("%s = %s" % [_charge_key(i), E.NAMES[picking[i]]])
		keys_label.text = "   ".join(keys)
	combos = Loadout.charges(picking)
	combo_index = clampi(combo_index, 0, maxi(combos.size() - 1, 0))
	_build_combo_rows()
	_refresh_combo()


func _build_combo_rows() -> void:
	for child in combo_list.get_children():
		combo_list.remove_child(child)
		child.queue_free()
	var last_size := 0
	for i in combos.size():
		var combo: Dictionary = combos[i]
		if combo.keys.size() != last_size:
			last_size = combo.keys.size()
			var group := _label(combo_list, "%d toque(s)" % last_size, 13)
			group.add_theme_color_override("font_color", Color(0.65, 0.68, 0.8))
		var button := _button(combo_list, "", _on_combo_pressed.bind(i))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 38)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 4)
		row.offset_left = 8
		button.add_child(row)
		var keys := _label(row, _keys_text(combo.keys), 13)
		keys.custom_minimum_size.x = 52
		keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for element in combo.charge:
			var dot := _icon(row, "slot", Vector2(26, 26))
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.set_view({"glyph": Glyphs.element_id(element), "glyph_color": E.COLORS[element]})
		var ultimate := _label(row, "", 12)
		ultimate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ultimate.clip_text = true
		ultimate.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ultimate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ultimate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ultimate.text = Ultimates.label(Ultimates.resolve(combo.charge)) + "  "
		if Ultimates.is_mega(combo.charge):
			ultimate.text = "MEGA " + ultimate.text
			ultimate.add_theme_color_override("font_color", GOLD)
		button.tooltip_text = "%s — ultimate: %s" % [ElementInfo.names(combo.charge), ultimate.text.strip_edges()]


func _refresh_combo() -> void:
	var rows := combo_list.get_children().filter(func(child): return child is Button)
	for i in rows.size():
		rows[i].set_pressed_no_signal(i == combo_index)
	var charge: Array = combos[combo_index].charge if not combos.is_empty() else []
	for i in combo_slots.size():
		var filled := i < charge.size()
		combo_slots[i].set_view({"filled": filled, "glyph": Glyphs.element_id(charge[i]) if filled else "",
			"glyph_color": E.COLORS[charge[i]] if filled else Color.WHITE})
	if charge.is_empty():
		combo_title.text = "Sem carga"
		combo_effects.text = "Escolha 3 elementos para ver as combinações."
	else:
		combo_title.text = "%s   (%s)" % [ElementInfo.names(charge), _keys_text(combos[combo_index].keys)]
		combo_effects.text = ElementInfo.describe(ElementInfo.EFFECTS, charge)

	var info := Classes.info(class_id)
	for id in Classes.SLOTS:
		var skill: Dictionary = info.skills[id]
		var title: String = skill.label
		var mega := false
		if id == "r" and not charge.is_empty():
			title = Ultimates.label(Ultimates.resolve(charge))
			mega = Ultimates.is_mega(charge)
		skill_icons[id].set_view({"glyph": skill.id,
			"glyph_color": Vfx.mix_color(charge).lightened(0.2) if not charge.is_empty() else Color(0.85, 0.85, 1.0),
			"key_text": Keybinds.action_text(SKILL_ACTIONS[id]), "title": title,
			"detail": "%d mana" % roundi(skill.cost), "state": "ready" if id == slot else "nomana", "mega": mega})
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.set_border_width_all(3)
		style.set_corner_radius_all(12)
		style.border_color = GOLD if id == slot else Color(0, 0, 0, 0)
		skill_cards[id].add_theme_stylebox_override("panel", style)
	var selected: Dictionary = info.skills[slot]
	preview.show_skill(selected, charge)
	var lines := SkillText.lines(selected, charge, Keybinds.action_text(SKILL_ACTIONS[slot]))
	lines[0] = "[b]%s[/b]" % lines[0]
	description.text = "\n".join(lines)


# --- Montagem ---

func _charge_key(index: int) -> String:
	return Keybinds.action_text(CHARGE_ACTIONS[index])


func _keys_text(keys: Array) -> String:
	return " ".join(keys.map(func(index): return _charge_key(index)))


func _panel(parent: Node, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column


func _icon(parent: Node, mode: String, icon_size: Vector2) -> Control:
	var icon := SkillIcon.new()
	icon.mode = mode
	icon.custom_minimum_size = icon_size
	icon.size = icon_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
