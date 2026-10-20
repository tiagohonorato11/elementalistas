# HUD: fila de elementos, vida, onda atual, feitiços especiais, avisos e ajuda de controles.
extends CanvasLayer

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")
const Specials = preload("res://scripts/core/specials.gd")

const ELEMENT_ACTION_IDS := {
	E.Type.WATER: "element_water", E.Type.LIFE: "element_life", E.Type.SHIELD: "element_shield",
	E.Type.COLD: "element_cold", E.Type.LIGHTNING: "element_lightning", E.Type.ARCANE: "element_arcane",
	E.Type.EARTH: "element_earth", E.Type.FIRE: "element_fire",
}

var player: Node
var game_state: Node
var status_label: Label
var wave_label: Label
var specials_label: Label
var banner: Label
var _recipe_keys := {}   # id do especial -> teclas da receita (ex.: "V C V C")


func _ready() -> void:
	status_label = _make_label(26)
	status_label.position = Vector2(16, 16)
	var help := _make_label(16)
	help.position = Vector2(16, 630)
	help.text = _help_text()

	wave_label = _make_label(26)
	wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.offset_left = -420
	wave_label.offset_right = -16
	wave_label.offset_top = 16

	specials_label = _make_label(17)
	specials_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	specials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	specials_label.offset_left = -520
	specials_label.offset_right = -16
	specials_label.offset_top = 110
	for id in Specials.ORDER:
		var keys := PackedStringArray()
		for element in Specials.SPECIALS[id].recipe:
			keys.append(Keybinds.action_text(ELEMENT_ACTION_IDS[element]))
		_recipe_keys[id] = " ".join(keys)

	banner = _make_label(40)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.offset_left = -500
	banner.offset_right = 500
	banner.offset_top = -120
	banner.offset_bottom = -20


func _process(_delta: float) -> void:
	_update_status()
	_update_wave()
	_update_specials()


func _update_status() -> void:
	if not is_instance_valid(player):
		status_label.text = "Aguardando jogadores..."
		return
	var names := PackedStringArray()
	for element in player.queue_view:
		names.append(E.NAMES[element])
	var queue_text := "(vazia)" if names.is_empty() else ", ".join(names)
	var shape := SpellResolver.resolve_shape(player.queue_view)
	var spell_text: String = SpellResolver.SHAPE_NAMES[shape]
	var special := Specials.match_special(player.queue_view)
	if not special.is_empty():
		spell_text += "  (ou especial: %s)" % Specials.SPECIALS[special].label
	if player.fx_shape == SpellResolver.Shape.PROJECTILE:
		spell_text = "Carregando projétil: %d%%" % roundi(player.fx_length * 100.0)
	elif player.auto_cast_timer > 0.0:
		spell_text += "  — lança em %.1f s" % player.auto_cast_timer
	var ability: String = player.cls.ability_label
	var ability_state := "pronta" if player.ability_cooldown <= 0.0 else "%ds" % ceili(player.ability_cooldown)
	var class_text := "%s | %s (%s): %s" % [
		player.cls.label, ability, Keybinds.action_text("class_ability"), ability_state]
	if player.weapon_charges > 0:
		var weapon_names := PackedStringArray()
		for element in player.weapon_elements:
			weapon_names.append(E.NAMES[element])
		class_text += " | Arma: %s x%d" % [", ".join(weapon_names), player.weapon_charges]
	if player.invisible > 0.0:
		class_text += " | INVISÍVEL"
	status_label.text = "%s\nFila: %s\nFeitiço: %s\nVida: %d/%d %s\nJogadores: %d" % [
		class_text,
		queue_text,
		spell_text,
		ceili(player.health.hp),
		ceili(player.health.max_hp),
		player.health.status_text(),
		Network.players.size(),
	]


func _update_specials() -> void:
	if not is_instance_valid(player):
		specials_label.text = ""
		return
	var lines := PackedStringArray(["Especiais (%s com a receita na fila):" % Keybinds.action_text("cast_special")])
	for id in Specials.ORDER:
		var left: float = player.special_cooldowns.get(id, 0.0)
		var state := "pronto" if left <= 0.0 else "%ds" % ceili(left)
		lines.append("%s  [%s]  %s" % [Specials.SPECIALS[id].label, _recipe_keys[id], state])
	specials_label.text = "\n".join(lines)


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
		banner.text = "Você caiu!\nUm aliado pode te reviver com Vida."


# Ajuda montada com as teclas que o jogador configurou.
func _help_text() -> String:
	var elements := PackedStringArray()
	for element in ELEMENT_ACTION_IDS:
		elements.append("%s %s" % [Keybinds.action_text(ELEMENT_ACTION_IDS[element]), E.NAMES[element]])
	var k := func(id): return Keybinds.action_text(id)
	var lines := PackedStringArray([
		"Elementos: " + " | ".join(elements),
		"Andar: %s no chão | Lançar: monte a combinação e espere 1 s (mira no mouse) | Golpe: %s" % [
			k.call("move_to_cursor"), k.call("cast_weapon")],
		"Área: %s | Em si mesmo: %s | Especial: %s | Habilidade: %s | Esc: sair para o lobby" % [
			k.call("cast_area"), k.call("cast_self"), k.call("cast_special"), k.call("class_ability")],
	])
	return "\n".join(lines)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
