# HUD: skills (Q W E R) com ícones desenhados, recarga, custo e dicas; mana;
# carga de elementos (D F G); vida, onda, prévia do ultimate e avisos; tela de
# ajuda (F1); placar no fim da partida; flash de tela nos impactos grandes.
extends CanvasLayer

const E = preload("res://scripts/core/elements.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaState = preload("res://scripts/moba/moba_state.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const PracticeState = preload("res://scripts/practice/practice_state.gd")
const PracticePanel = preload("res://scripts/practice/practice_panel.gd")
const WorldState = preload("res://scripts/world/world_state.gd")
const WorldMap = preload("res://scripts/world/world_map.gd")
const Quests = preload("res://scripts/world/quests.gd")
const SkillIcon = preload("res://scripts/ui/skill_icon.gd")
const Glyphs = preload("res://scripts/ui/glyphs.gd")
const ElementInfo = preload("res://scripts/core/element_info.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const CHARGE_ACTIONS := ["charge_1", "charge_2", "charge_3"]
const SKILL_ACTIONS := {"q": "skill_q", "w": "skill_w", "e": "skill_e", "r": "skill_r"}
const SKILL_GLYPH_COLOR := Color(0.85, 0.85, 1.0)
const SCORE_REFRESH := 0.5

var player: Node
var game_state: Node
var status_label: Label
var wave_label: Label
var specials_label: Label   # prévia do ultimate com a carga atual
var banner: Label
var shop_panel: PanelContainer
var shop_status: Label
var shop_buttons := {}   # id do item -> Button
var _slots: Array = []   # SkillIcon dos 3 espaços da carga
var _skill_icons := {}   # slot -> SkillIcon
var _legend: Array = []  # SkillIcon das teclas D F G
var _legend_shown: Array = []
var help_panel: PanelContainer   # tela de ajuda (F1)
var score_panel: PanelContainer  # placar do fim da partida
var _score_label: RichTextLabel
var _score_timer := 0.0
var flash_rect: ColorRect        # clarão nos impactos grandes
var mana_bar: ProgressBar
var mana_label: Label
var minimap: Control
var blackout_rect: ColorRect   # Mega fumaça: a visão some
var practice_panel: Control    # modo Treino
var dialog_panel: PanelContainer   # Mundo: conversa com a Anciã
var _dialog_text: Label
var _dialog_button: Button


func _ready() -> void:
	status_label = _make_label(26)
	status_label.position = Vector2(16, 16)
	var help := _make_label(15)
	help.position = Vector2(16, 694)
	help.text = _help_text()
	_build_skill_row()
	_build_mana_bar()
	_build_queue_row()
	_build_legend_row()
	blackout_rect = ColorRect.new()
	blackout_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blackout_rect.color = Color(0.08, 0.08, 0.09, 0.93)
	blackout_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout_rect.visible = false
	add_child(blackout_rect)
	move_child(blackout_rect, 0)
	minimap = Minimap.new()
	minimap.main = get_parent()
	add_child(minimap)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	add_child(flash_rect)

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


func _process(delta: float) -> void:
	flash_rect.color.a = maxf(flash_rect.color.a - delta * 1.6, 0.0)
	_update_score(delta)
	var dark: bool = is_instance_valid(player) and player.health.blackout > 0.0
	blackout_rect.visible = dark
	minimap.visible = not dark
	_update_status()
	_update_queue_row()
	_update_skills()
	if game_state is MobaState:
		_update_moba()
	elif game_state is PracticeState:
		_update_practice()
	elif game_state is WorldState:
		_update_world()
	else:
		_update_wave()
	_update_specials()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop") and (game_state is MobaState or game_state is WorldState):
		_toggle_shop()
	elif event.is_action_pressed("practice_panel") and practice_panel != null:
		practice_panel.visible = not practice_panel.visible
	elif event.is_action_pressed("help"):
		_toggle_help()


# Clarão de tela (impactos grandes, como as versões MEGA).
func flash(color: Color, strength: float) -> void:
	flash_rect.color = Color(color, maxf(flash_rect.color.a, clampf(strength, 0.0, 0.6)))


# --- Mundo -------------------------------------------------------------------

func _update_world() -> void:
	banner.text = ""
	if not is_instance_valid(player):
		wave_label.text = ""
		return
	var lines := PackedStringArray([
		"Mundo — %s" % WorldMap.zone_at(player.global_position),
		"Nível %d (%d/%d xp) | Ouro: %d" % [player.level, player.xp, Progression.xp_to_next(player.level), player.gold],
		"Missão: %s" % Quests.tracker(player.quests),
	])
	if player.is_at_shop() and not player.health.dead:
		lines.append("%s: loja do Ferreiro" % Keybinds.action_text("shop"))
	wave_label.text = "\n".join(lines)
	if player.health.dead:
		banner.text = "Você caiu! Volta à vila em %d s." % ceili(player.respawn_time)
	_update_dialog()
	_update_shop()


# Perto da Anciã: a conversa com a missão (aceitar, quanto falta, entregar).
func _update_dialog() -> void:
	var near: bool = player.near_elder()
	if dialog_panel == null:
		if not near:
			return
		dialog_panel = PanelContainer.new()
		dialog_panel.position = Vector2(16, 140)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.06, 0.04, 0.9)
		style.border_color = Color(0.85, 0.7, 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		dialog_panel.add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		dialog_panel.add_child(column)
		var title := Label.new()
		title.text = "Anciã Lira"
		title.add_theme_font_size_override("font_size", 19)
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		column.add_child(title)
		_dialog_text = Label.new()
		_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_dialog_text.custom_minimum_size.x = 400
		_dialog_text.add_theme_font_size_override("font_size", 15)
		column.add_child(_dialog_text)
		_dialog_button = Button.new()
		_dialog_button.focus_mode = Control.FOCUS_NONE
		_dialog_button.pressed.connect(_on_dialog_pressed)
		column.add_child(_dialog_button)
		add_child(dialog_panel)
	dialog_panel.visible = near
	if not near:
		return
	var active := Quests.active(player.quests)
	var offer := Quests.next_offer(player.quests)
	var text := ""
	var button := ""
	if not active.is_empty() and Quests.is_complete(player.quests, active):
		var quest := Quests.info(active)
		text = quest.done
		button = "Entregar (+%d de ouro, +%d de xp)" % [quest.gold, quest.xp]
	elif not active.is_empty():
		text = "%s\nAinda falta: %s" % [Quests.info(active).offer, Quests.tracker(player.quests)]
	elif not offer.is_empty():
		var quest := Quests.info(offer)
		text = "%s\n\nRecompensa: %d de ouro e %d de xp." % [quest.offer, quest.gold, quest.xp]
		button = "Aceitar: %s" % quest.title
	else:
		text = "Você já ajudou a vila em tudo que eu precisava. Volte mais tarde, viajante."
	_dialog_text.text = text
	_dialog_button.text = button
	_dialog_button.visible = not button.is_empty()


func _on_dialog_pressed() -> void:
	var active := Quests.active(player.quests)
	if not active.is_empty() and Quests.is_complete(player.quests, active):
		player.request_quest.rpc_id(1, "turn_in")
	else:
		player.request_quest.rpc_id(1, "accept")


# --- Treino ------------------------------------------------------------------

func _update_practice() -> void:
	banner.text = ""
	if practice_panel == null:
		practice_panel = PracticePanel.new()
		practice_panel.state = game_state
		add_child(practice_panel)
	practice_panel.player = player
	var on := PackedStringArray()
	for id in PracticeState.OPTIONS:
		if game_state.get(id):
			on.append(PracticeState.OPTIONS[id])
	wave_label.text = "Treino%s\nPainel: %s" % [
		(" | " + ", ".join(on)) if not on.is_empty() else "", Keybinds.action_text("practice_panel")]
	if is_instance_valid(player) and player.health.dead:
		banner.text = "Você caiu! Volta em instantes."


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
	var shop_place := "o Ferreiro da vila" if game_state is WorldState else "a fonte da base"
	var hint := "" if at_shop else "Vá até %s para comprar.\n" % shop_place
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
		specials_label.text = "Ultimate (%s): carregue elementos (3 iguais = MEGA)" % key
		return
	var title := Ultimates.label(id)
	if Ultimates.is_mega(player.queue_view):
		title = "MEGA " + title
	specials_label.text = "Ultimate (%s): %s\n%s" % [key, title, Ultimates.ULTIMATES[id].description]
	var zones := Ultimates.zone_elements(player.queue_view)
	if not zones.is_empty():
		var names := PackedStringArray()
		for element in zones:
			names.append(E.NAMES[element])
		specials_label.text += "\n+ zona de " + ", ".join(names)


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

func _icon(parent: Control, size: Vector2, mode: String) -> Control:
	var icon := SkillIcon.new()
	icon.mode = mode
	icon.custom_minimum_size = size
	parent.add_child(icon)
	return icon


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
	var row := _bottom_row(-240, -168)
	for slot in Classes.SLOTS:
		_skill_icons[slot] = _icon(row, Vector2(104, 72), "skill")


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
		_slots.append(_icon(row, Vector2(52, 52), "slot"))


# Legenda: tecla D F G com o elemento escolhido, na cor dele.
func _build_legend_row() -> void:
	var row := _bottom_row(-80, -50)
	for i in CHARGE_ACTIONS.size():
		_legend.append(_icon(row, Vector2(104, 30), "legend"))


func _update_skills() -> void:
	if not is_instance_valid(player):
		return
	if player.elements != _legend_shown:
		_legend_shown = player.elements.duplicate()
		for i in _legend.size():
			var element: int = player.elements[i]
			_legend[i].set_view({"glyph": Glyphs.element_id(element), "glyph_color": E.COLORS[element],
				"key_text": Keybinds.action_text(CHARGE_ACTIONS[i]), "title": E.NAMES[element]})
			_legend[i].tooltip_text = "%s: %s" % [E.NAMES[element], ElementInfo.EFFECTS[element]]
	mana_bar.max_value = maxf(player.max_mana, 1.0)
	mana_bar.value = player.mana
	mana_label.text = "Mana %d/%d" % [floori(player.mana), roundi(player.max_mana)]
	var charge: Array = player.queue_view
	for slot in _skill_icons:
		var skill: Dictionary = player.cls.skills[slot]
		var left: float = player.skill_cooldowns.get(slot, 0.0)
		var state := "ready"
		var detail := "%d mana" % roundi(skill.cost)
		if left > 0.0:
			state = "cooldown"
			detail = "%.1fs" % left if left < 10.0 else "%ds" % ceili(left)
		elif player.health.silenced > 0.0:
			state = "silenced"
			detail = "silenciado"
		elif player.mana < skill.cost:
			state = "nomana"
			detail = "sem mana"
		var skill_name: String = skill.label
		var glyph_color := SKILL_GLYPH_COLOR
		var mega := false
		if slot == "r":
			var id := Ultimates.resolve(charge)
			skill_name = Ultimates.label(id) if not id.is_empty() else "Ultimate"
			mega = Ultimates.is_mega(charge)
		if not charge.is_empty():
			glyph_color = Vfx.mix_color(charge).lightened(0.2)
		var hold: float = player.hold_progress() if skill.has("hold") else 0.0
		if hold > 0.0:
			detail = "escudo %d%%" % roundi(hold * 100.0)
		var full_cooldown: float = skill.cooldown * player.cooldown_mult
		var icon: Control = _skill_icons[slot]
		icon.set_view({"glyph": skill.id, "glyph_color": glyph_color,
			"key_text": Keybinds.action_text(SKILL_ACTIONS[slot]), "title": skill_name, "detail": detail,
			"state": state, "cooldown_ratio": clampf(left / maxf(full_cooldown, 0.01), 0.0, 1.0),
			"mega": mega, "hold": hold, "denied_at": player.denied.get(slot, -100000)})
		var tip := _skill_tooltip(slot, skill, charge)
		if icon.tooltip_text != tip:
			icon.tooltip_text = tip


# Dica do ícone: o que a skill faz e o que a carga atual muda nela.
func _skill_tooltip(slot: String, skill: Dictionary, charge: Array) -> String:
	var lines := PackedStringArray(["%s (%s) — %d de mana, recarga de %d s" % [
		skill.label, Keybinds.action_text(SKILL_ACTIONS[slot]), roundi(skill.cost), roundi(skill.cooldown)],
		skill.get("description", "")])
	match skill.id:
		"orb":
			if not charge.is_empty():
				lines.append("Com a carga: explode em área de %.1f m (%s)." % [
					Projectile.splash_radius_for(charge), ElementInfo.names(charge)])
		"mini_meteor":
			if not charge.is_empty():
				lines.append("Zona: " + ElementInfo.describe(ElementInfo.ZONES, charge))
		"bless_curse":
			if not charge.is_empty():
				lines.append("Carga: " + ElementInfo.names(charge))
				lines.append("Bolha (segurar): " + ElementInfo.describe(ElementInfo.BUBBLE, charge))
		"ultimate":
			var id := Ultimates.resolve(charge)
			if id.is_empty():
				lines.append("Carregue elementos (3 iguais = MEGA).")
			else:
				lines.append("%s%s: %s" % ["MEGA " if Ultimates.is_mega(charge) else "", Ultimates.label(id),
					Ultimates.ULTIMATES[id].description])
				var zones := Ultimates.zone_elements(charge)
				if not zones.is_empty():
					lines.append("Zonas: " + ElementInfo.describe(ElementInfo.ZONES, zones))
		_:
			if not charge.is_empty():
				lines.append("Carga: " + ElementInfo.describe(ElementInfo.EFFECTS, charge))
	if not skill.has("hold"):
		lines.append("Segure a tecla para ver a mira; solte para lançar.")
	return "\n".join(lines)


const ELEMENT_SOUNDS := {
	E.Type.WATER: "element_water", E.Type.LIFE: "element_life", E.Type.SHIELD: "element_shield",
	E.Type.COLD: "element_cold", E.Type.LIGHTNING: "element_lightning", E.Type.ARCANE: "element_arcane",
	E.Type.EARTH: "element_earth", E.Type.FIRE: "element_fire", E.Type.STEAM: "element_water",
	E.Type.ICE: "element_cold", E.Type.VOID: "element_void", E.Type.GRAVITY: "element_gravity",
	E.Type.SMOKE: "element_smoke", E.Type.BLOOD: "element_blood",
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
		var filled := i < queue.size()
		var element: int = queue[i] if filled else -1
		_slots[i].set_view({"filled": filled, "glyph": Glyphs.element_id(element) if filled else "",
			"glyph_color": E.COLORS[element] if filled else Color.WHITE})
		_slots[i].tooltip_text = "%s: %s" % [E.NAMES[element], ElementInfo.EFFECTS[element]] if filled else ""


# Linha de ajuda curta (a completa fica na tela de ajuda).
func _help_text() -> String:
	var k := func(id): return Keybinds.action_text(id)
	return "%s: ajuda | Carga: %s %s %s | Skills: %s %s %s %s (segure para mirar, solte para lançar) | Esc: lobby" % [
		k.call("help"), k.call("charge_1"), k.call("charge_2"), k.call("charge_3"),
		k.call("skill_q"), k.call("skill_w"), k.call("skill_e"), k.call("skill_r")]


# --- Tela de ajuda (F1) ----------------------------------------------------------

func _toggle_help() -> void:
	if help_panel == null:
		help_panel = PanelContainer.new()
		help_panel.set_anchors_preset(Control.PRESET_CENTER)
		help_panel.offset_left = -430
		help_panel.offset_right = 430
		help_panel.offset_top = -300
		help_panel.offset_bottom = 300
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.05, 0.09, 0.94)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(16)
		help_panel.add_theme_stylebox_override("panel", style)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.scroll_active = true
		text.add_theme_font_size_override("normal_font_size", 15)
		text.add_theme_font_size_override("bold_font_size", 17)
		text.text = _help_bbcode()
		help_panel.add_child(text)
		add_child(help_panel)
		help_panel.visible = false
	help_panel.visible = not help_panel.visible
	Audio.play("open" if help_panel.visible else "close")


static func _hex(element: int) -> String:
	return E.COLORS[element].lightened(0.25).to_html(false)


func _element_name(element: int) -> String:
	return "[color=#%s]%s[/color]" % [_hex(element), E.NAMES[element]]


func _help_bbcode() -> String:
	var k := func(id): return Keybinds.action_text(id)
	var out := PackedStringArray()
	out.append("[center][b]Como jogar[/b]   (%s fecha)[/center]" % k.call("help"))
	out.append("• Andar: %s no chão. Golpe básico: %s (não usa a carga)." % [k.call("move_to_cursor"), k.call("cast_weapon")])
	out.append("• %s %s %s carregam os 3 elementos escolhidos no lobby: até 3, pode repetir. A [b]próxima skill[/b] usa toda a carga." % [
		k.call("charge_1"), k.call("charge_2"), k.call("charge_3")])
	out.append("• %s %s %s %s: skills. Segure Q, E ou R para ver a área; solte para lançar. W: no aliado (ou ninguém) ajuda, no inimigo enfraquece. Mago: segure W 1,5 s para a bolha de escudo." % [
		k.call("skill_q"), k.call("skill_w"), k.call("skill_e"), k.call("skill_r")])
	out.append("• Passe o mouse nos ícones das skills para ver o que a carga atual faz.")
	out.append("")
	out.append("[b]Fusões e opostos[/b]")
	var fusions := PackedStringArray()
	for rule in E.FUSIONS:
		fusions.append("%s + %s = %s" % [_element_name(rule[0]), _element_name(rule[1]), _element_name(rule[2])])
	out.append("Fusões: " + ", ".join(fusions) + ".")
	var opposites := PackedStringArray()
	for pair in E.OPPOSITES:
		opposites.append("%s×%s" % [_element_name(pair[0]), _element_name(pair[1])])
	out.append("Opostos (não podem ser escolhidos juntos): " + ", ".join(opposites) + ".")
	out.append("")
	out.append("[b]Elementos[/b]")
	for element in Loadout.BASIC + [E.Type.STEAM, E.Type.ICE]:
		out.append("%s: %s. [i]Zona:[/i] %s." % [_element_name(element), ElementInfo.EFFECTS[element],
			ElementInfo.ZONES.get(element, "—")])
	out.append("")
	out.append("[b]Ultimate (R)[/b]: o elemento que mais aparece na carga decide; os outros deixam a zona deles no local. [color=#ffd24a]3 iguais = versão MEGA.[/color]")
	for element in Loadout.BASIC:
		var normal: String = Ultimates.BY_ELEMENT[element]
		var mega: String = Ultimates.MEGA_BY_ELEMENT[element]
		out.append("%s: %s — %s.  [color=#ffd24a]MEGA: %s[/color] — %s." % [_element_name(element),
			Ultimates.label(normal), Ultimates.ULTIMATES[normal].description,
			Ultimates.label(mega), Ultimates.ULTIMATES[mega].description])
	return "\n".join(out)


# --- Placar do fim da partida --------------------------------------------------

func _match_over() -> bool:
	if not is_instance_valid(game_state):
		return false
	if game_state is MobaState:
		return game_state.is_over()
	if game_state is GameState:
		return game_state.phase == GameState.Phase.VICTORY or game_state.phase == GameState.Phase.DEFEAT
	return false


func _update_score(delta: float) -> void:
	var over := _match_over()
	if score_panel == null:
		if not over:
			return
		score_panel = PanelContainer.new()
		score_panel.set_anchors_preset(Control.PRESET_CENTER)
		score_panel.offset_left = -330
		score_panel.offset_right = 330
		score_panel.offset_top = 0
		score_panel.offset_bottom = 10
		score_panel.grow_vertical = Control.GROW_DIRECTION_END
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.05, 0.09, 0.85)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(12)
		score_panel.add_theme_stylebox_override("panel", style)
		_score_label = RichTextLabel.new()
		_score_label.bbcode_enabled = true
		_score_label.fit_content = true
		_score_label.add_theme_font_size_override("normal_font_size", 15)
		_score_label.add_theme_font_size_override("bold_font_size", 15)
		score_panel.add_child(_score_label)
		add_child(score_panel)
	score_panel.visible = over
	_score_timer -= delta
	if over and _score_timer <= 0.0:
		_score_timer = SCORE_REFRESH
		_score_label.text = _score_bbcode()


func _score_bbcode() -> String:
	var moba := game_state is MobaState
	var rows: Array = get_tree().get_nodes_in_group("players").filter(func(node): return not node.is_queued_for_deletion())
	rows.sort_custom(func(a, b): return a.stat_damage > b.stat_damage)
	var out := "[center][b]Placar[/b][/center]\n[table=5]"
	for header in ["Jogador", "Classe", "Dano", "Cura", "Abates"]:
		out += "[cell][b]%s[/b]   [/cell]" % header
	for node in rows:
		var who := _player_name(node)
		if moba:
			who = "[color=#%s]%s[/color]" % [Combat.TEAM_COLORS[node.team].to_html(false), who]
		out += "[cell]%s   [/cell][cell]%s   [/cell][cell]%d   [/cell][cell]%d   [/cell][cell]%d[/cell]" % [
			who, node.cls.label, roundi(node.stat_damage), roundi(node.stat_healing), node.stat_kills]
	return out + "[/table]"


func _player_name(node: Node) -> String:
	if node.is_bot:
		return "Bot"
	var index: int = Network.players.find(node.peer_id)
	var who := "Host" if node.peer_id == 1 else "Jogador %d" % (index + 1)
	if node == player:
		who += " (você)"
	return who


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
