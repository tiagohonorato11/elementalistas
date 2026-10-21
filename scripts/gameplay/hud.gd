# HUD: skills (Q W E R) com recarga e custo, mana, carga de elementos (D F G),
# vida, onda/placar, prévia do ultimate, avisos e ajuda de controles.
extends CanvasLayer

const E = preload("res://scripts/core/elements.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaState = preload("res://scripts/moba/moba_state.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")

const CHARGE_ACTIONS := ["charge_1", "charge_2", "charge_3"]
const SKILL_ACTIONS := {"q": "skill_q", "w": "skill_w", "e": "skill_e", "r": "skill_r"}
const COOLDOWN_COLOR := Color(0.25, 0.25, 0.3)
const READY_COLOR := Color(0.35, 0.3, 0.6)
const NO_MANA_COLOR := Color(0.25, 0.3, 0.55)

var player: Node
var game_state: Node
var status_label: Label
var wave_label: Label
var specials_label: Label   # prévia do ultimate com a carga atual
var banner: Label
var shop_panel: PanelContainer
var shop_status: Label
var shop_buttons := {}   # id do item -> Button
var _slots: Array = []   # [PanelContainer, Label] dos 3 espaços da carga
var _skill_icons := {}   # slot -> [PanelContainer, Label]
var _legend: Array = []  # [PanelContainer, Label] das teclas D F G
var _legend_shown: Array = []
var mana_bar: ProgressBar
var mana_label: Label

const SHORT_NAMES := {
	E.Type.WATER: "Água", E.Type.LIFE: "Vida", E.Type.SHIELD: "Esc.", E.Type.COLD: "Frio",
	E.Type.LIGHTNING: "Raio", E.Type.ARCANE: "Arc.", E.Type.EARTH: "Terra", E.Type.FIRE: "Fogo",
	E.Type.STEAM: "Vapor", E.Type.ICE: "Gelo",
	E.Type.VOID: "Vazio", E.Type.GRAVITY: "Grav.", E.Type.SMOKE: "Fum.",
}


func _ready() -> void:
	status_label = _make_label(26)
	status_label.position = Vector2(16, 16)
	var help := _make_label(15)
	help.position = Vector2(16, 676)
	help.text = _help_text()
	_build_skill_row()
	_build_mana_bar()
	_build_queue_row()
	_build_legend_row()
	var minimap := Minimap.new()
	minimap.main = get_parent()
	add_child(minimap)

	wave_label = _make_label(21)
	wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.offset_left = -760
	wave_label.offset_right = -16
	wave_label.offset_top = 16

	specials_label = _make_label(17)
	specials_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	specials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	specials_label.offset_left = -520
	specials_label.offset_right = -16
	specials_label.offset_top = 110

	banner = _make_label(40)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.offset_left = -500
	banner.offset_right = 500
	banner.offset_top = -120
	banner.offset_bottom = -20


func _process(_delta: float) -> void:
	_update_status()
	_update_queue_row()
	_update_skills()
	if game_state is MobaState:
		_update_moba()
	else:
		_update_wave()
	_update_specials()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop") and game_state is MobaState:
		_toggle_shop()


# --- MOBA --------------------------------------------------------------------

func _update_moba() -> void:
	specials_label.offset_top = 210
	banner.text = ""
	if not is_instance_valid(player):
		wave_label.text = ""
		return
	var state: MobaState = game_state
	var lines := PackedStringArray([
		"Time %s | Nível %d (%d/%d xp) | Ouro: %d" % [
			Combat.TEAM_NAMES[player.team], player.level, player.xp,
			Progression.xp_to_next(player.level), player.gold],
		"Tempo %d:%02d | Próxima leva em %ds" % [
			int(state.game_time) / 60, int(state.game_time) % 60, ceili(state.wave_timer)],
		"Torres de pé: Azul %d | Vermelho %d" % [
			state.standing(Combat.BLUE, "tower"), state.standing(Combat.RED, "tower")],
		"Guardião: %s" % ("renasce em %ds" % ceili(state.boss_timer) if state.boss_timer > 0.0 else "no fosso central"),
	])
	if not player.buffs.is_empty():
		var names := PackedStringArray()
		for id in player.buffs:
			names.append("%s %ds" % [Progression.BUFFS[id].label, ceili(player.buffs[id])])
		lines.append("Bônus: " + ", ".join(names))
	lines.append("Loja: %s (na fonte da base)" % Keybinds.action_text("shop"))
	wave_label.text = "\n".join(lines)

	var restart_hint := "R: jogar de novo | Esc: lobby" if multiplayer.is_server() \
			else "Aguardando o host (R) | Esc: lobby"
	if state.is_over():
		var won: bool = state.winner == player.team
		banner.text = "%s O time %s destruiu o nexus.\n%s" % [
			"VITÓRIA!" if won else "DERROTA...", Combat.TEAM_NAMES[state.winner], restart_hint]
	elif player.health.dead:
		banner.text = "Você caiu! Volta na base em %d s." % ceili(player.respawn_time)
	_update_shop()


func _build_shop() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(16, 220)
	shop_panel.visible = false
	add_child(shop_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	shop_panel.add_child(column)
	var title := Label.new()
	title.text = "Loja (até %d itens)" % Progression.MAX_ITEMS
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	for id in Progression.ITEM_ORDER:
		var item: Dictionary = Progression.ITEMS[id]
		var button := Button.new()
		button.text = "%s — %d de ouro (%s)" % [item.label, item.cost, item.description]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func(): player.request_buy.rpc_id(1, id))
		column.add_child(button)
		shop_buttons[id] = button
	shop_status = Label.new()
	column.add_child(shop_status)


func _toggle_shop() -> void:
	if shop_panel == null:
		_build_shop()
	shop_panel.visible = not shop_panel.visible


func _update_shop() -> void:
	if shop_panel == null or not shop_panel.visible:
		return
	var at_shop: bool = player.is_at_shop()
	for id in shop_buttons:
		shop_buttons[id].disabled = not Progression.cannot_buy(id, player.gold, player.items, at_shop).is_empty()
	var owned := PackedStringArray()
	for id in player.items:
		owned.append(Progression.ITEMS[id].label)
	var hint := "" if at_shop else "Volte à fonte da base para comprar.\n"
	shop_status.text = "%sOuro: %d | Itens: %s" % [hint, player.gold, ", ".join(owned) if not owned.is_empty() else "nenhum"]


func _update_status() -> void:
	if not is_instance_valid(player):
		status_label.text = "Aguardando jogadores..."
		return
	var class_text: String = player.cls.label
	if player.invisible > 0.0:
		class_text += " | INVISÍVEL"
	status_label.text = "%s\nVida: %d/%d %s\nJogadores: %d" % [
		class_text,
		ceili(player.health.hp),
		ceili(player.health.max_hp),
		player.health.status_text(),
		Network.players.size(),
	]


# Qual ultimate a carga atual geraria (canto superior direito).
func _update_specials() -> void:
	if not is_instance_valid(player):
		specials_label.text = ""
		return
	var id := Ultimates.resolve(player.queue_view)
	var key := Keybinds.action_text("skill_r")
	if id.is_empty():
		specials_label.text = "Ultimate (%s): carregue elementos" % key
	else:
		specials_label.text = "Ultimate (%s): %s\n%s" % [key, Ultimates.label(id), Ultimates.ULTIMATES[id].description]


func _update_wave() -> void:
	banner.text = ""
	if not is_instance_valid(game_state):
		wave_label.text = ""
		return
	var total: int = game_state.total_waves()
	var restart_hint := "R: jogar de novo | Esc: lobby" if multiplayer.is_server() \
			else "Aguardando o host (R) | Esc: lobby"
	var phase: int = game_state.phase
	if phase == GameState.Phase.COUNTDOWN:
		wave_label.text = "Prepare-se!"
		banner.text = "Onda 1 em %d..." % ceili(game_state.timer)
	elif phase == GameState.Phase.FIGHTING:
		wave_label.text = "Onda %d/%d\nInimigos: %d" % [game_state.wave, total, game_state.enemies_left]
	elif phase == GameState.Phase.BREAK:
		wave_label.text = "Onda %d/%d concluída" % [game_state.wave, total]
		banner.text = "Próxima onda em %d..." % ceili(game_state.timer)
	elif phase == GameState.Phase.VICTORY:
		wave_label.text = "Onda %d/%d" % [game_state.wave, total]
		banner.text = "VITÓRIA!\n%s" % restart_hint
	elif phase == GameState.Phase.DEFEAT:
		wave_label.text = "Onda %d/%d" % [game_state.wave, total]
		banner.text = "DERROTA...\n%s" % restart_hint
	if banner.text.is_empty() and is_instance_valid(player) and player.health.dead:
		banner.text = "Você caiu!\nUm aliado pode te levantar com o W."


# --- Fila e legenda dos elementos (embaixo, no centro) -----------------------

func _slot_style(color: Color, filled: bool, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.92 if filled else 0.18)
	style.border_color = color.lightened(0.4) if filled else Color(1, 1, 1, 0.25)
	style.set_border_width_all(3 if filled else 2)
	style.set_corner_radius_all(radius)
	return style


func _icon(parent: Control, size: Vector2, font_size: int) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	panel.add_child(label)
	parent.add_child(panel)
	return [panel, label]


func _bottom_row(top: float, bottom: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -320
	row.offset_right = 320
	row.offset_top = top
	row.offset_bottom = bottom
	add_child(row)
	return row


# Skills Q W E R: nome, tecla, custo; escurece em recarga e azula sem mana.
func _build_skill_row() -> void:
	var row := _bottom_row(-236, -168)
	for slot in Classes.SLOTS:
		_skill_icons[slot] = _icon(row, Vector2(96, 68), 14)


func _build_mana_bar() -> void:
	mana_bar = ProgressBar.new()
	mana_bar.show_percentage = false
	mana_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mana_bar.offset_left = -200
	mana_bar.offset_right = 200
	mana_bar.offset_top = -162
	mana_bar.offset_bottom = -144
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.45, 1.0)
	fill.set_corner_radius_all(4)
	mana_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.1, 0.8)
	back.set_corner_radius_all(4)
	mana_bar.add_theme_stylebox_override("background", back)
	add_child(mana_bar)
	mana_label = Label.new()
	mana_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mana_label.add_theme_font_size_override("font_size", 13)
	mana_label.add_theme_color_override("font_outline_color", Color.BLACK)
	mana_label.add_theme_constant_override("outline_size", 4)
	mana_bar.add_child(mana_label)


# Carga: 3 espaços redondos com os elementos carregados.
func _build_queue_row() -> void:
	var row := _bottom_row(-138, -86)
	for i in 3:
		_slots.append(_icon(row, Vector2(52, 52), 14))


# Legenda: tecla D F G com o elemento escolhido, na cor dele.
func _build_legend_row() -> void:
	var row := _bottom_row(-80, -50)
	for i in CHARGE_ACTIONS.size():
		_legend.append(_icon(row, Vector2(92, 30), 14))


func _update_skills() -> void:
	if not is_instance_valid(player):
		return
	if player.elements != _legend_shown:
		_legend_shown = player.elements.duplicate()
		for i in _legend.size():
			var element: int = player.elements[i]
			_legend[i][0].add_theme_stylebox_override("panel", _slot_style(E.COLORS[element], true, 8))
			_legend[i][1].text = "%s %s" % [Keybinds.action_text(CHARGE_ACTIONS[i]), SHORT_NAMES[element]]
	mana_bar.max_value = maxf(player.max_mana, 1.0)
	mana_bar.value = player.mana
	mana_label.text = "Mana %d/%d" % [floori(player.mana), roundi(player.max_mana)]
	for slot in _skill_icons:
		var skill: Dictionary = player.cls.skills[slot]
		var left: float = player.skill_cooldowns.get(slot, 0.0)
		var color := READY_COLOR
		var state := "%d mana" % roundi(skill.cost)
		if left > 0.0:
			color = COOLDOWN_COLOR
			state = "%.1fs" % left if left < 10.0 else "%ds" % ceili(left)
		elif player.mana < skill.cost:
			color = NO_MANA_COLOR
			state = "sem mana"
		var skill_name: String = skill.label
		if slot == "r":
			var id := Ultimates.resolve(player.queue_view)
			skill_name = Ultimates.label(id) if not id.is_empty() else "Ultimate"
		var text := "%s  %s\n%s" % [Keybinds.action_text(SKILL_ACTIONS[slot]), skill_name, state]
		var panel: PanelContainer = _skill_icons[slot][0]
		var key := "%s|%s" % [text, color]
		if panel.get_meta("shown", "") == key:
			continue
		panel.set_meta("shown", key)
		panel.add_theme_stylebox_override("panel", _slot_style(color, left <= 0.0, 10))
		_skill_icons[slot][1].text = text


const ELEMENT_SOUNDS := {
	E.Type.WATER: "element_water", E.Type.LIFE: "element_life", E.Type.SHIELD: "element_shield",
	E.Type.COLD: "element_cold", E.Type.LIGHTNING: "element_lightning", E.Type.ARCANE: "element_arcane",
	E.Type.EARTH: "element_earth", E.Type.FIRE: "element_fire", E.Type.STEAM: "element_water",
	E.Type.ICE: "element_cold", E.Type.VOID: "element_void", E.Type.GRAVITY: "element_gravity",
	E.Type.SMOKE: "element_smoke",
}
var _last_queue: Array = []


func _update_queue_row() -> void:
	var queue: Array = player.queue_view if is_instance_valid(player) else []
	if queue != _last_queue:
		# Cresceu ou mudou (fusão Água+Fogo = Vapor): toca o último elemento.
		if not queue.is_empty() and (queue.size() >= _last_queue.size()):
			Audio.play(ELEMENT_SOUNDS.get(queue[-1], "select"), null, 0.0)
		_last_queue = queue.duplicate()
	for i in _slots.size():
		var panel: PanelContainer = _slots[i][0]
		var label: Label = _slots[i][1]
		var filled := i < queue.size()
		var element: int = queue[i] if filled else -1
		var key := "%d" % element
		if panel.get_meta("shown", "") == key:
			continue
		panel.set_meta("shown", key)
		var color: Color = E.COLORS[element] if filled else Color(0.2, 0.2, 0.25)
		panel.add_theme_stylebox_override("panel", _slot_style(color, filled, 30))
		label.text = SHORT_NAMES[element] if filled else ""


# Ajuda montada com as teclas que o jogador configurou.
func _help_text() -> String:
	var k := func(id): return Keybinds.action_text(id)
	var lines := PackedStringArray([
		"Andar: %s no chão | Golpe: %s | Carregar elementos: %s %s %s (até 3, a próxima skill usa)" % [
			k.call("move_to_cursor"), k.call("cast_weapon"), k.call("charge_1"), k.call("charge_2"), k.call("charge_3")],
		"Skills: %s %s %s %s (W: no aliado ou inimigo sob o mouse; R depende da carga) | Esc: sair para o lobby" % [
			k.call("skill_q"), k.call("skill_w"), k.call("skill_e"), k.call("skill_r")],
	])
	return "\n".join(lines)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
