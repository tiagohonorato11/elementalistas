# HUD: fila de elementos, vida, onda atual, avisos e ajuda de controles.
extends CanvasLayer

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")

const HELP := """Elementos: Q Água | W Vida | E Escudo | R Frio | A Raio | S Arcano | D Terra | F Fogo
Andar: segurar botão esquerdo (ou setas) | Lançar à frente: botão direito (segure para spray/beam/arco)
Área: Shift + botão direito | Em si mesmo: botão do meio ou Espaço | Esc: sair para o lobby"""

var player: Node
var game_state: Node
var status_label: Label
var wave_label: Label
var banner: Label


func _ready() -> void:
	status_label = _make_label(26)
	status_label.position = Vector2(16, 16)
	var help := _make_label(16)
	help.position = Vector2(16, 630)
	help.text = HELP

	wave_label = _make_label(26)
	wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.offset_left = -420
	wave_label.offset_right = -16
	wave_label.offset_top = 16

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


func _update_status() -> void:
	if not is_instance_valid(player):
		status_label.text = "Aguardando jogadores..."
		return
	var names := PackedStringArray()
	for element in player.queue_view:
		names.append(E.NAMES[element])
	var queue_text := "(vazia)" if names.is_empty() else ", ".join(names)
	var shape := SpellResolver.resolve_shape(player.queue_view)
	status_label.text = "Fila: %s\nFeitiço: %s\nVida: %d %s\nJogadores: %d" % [
		queue_text,
		SpellResolver.SHAPE_NAMES[shape],
		ceili(player.health.hp),
		player.health.status_text(),
		Network.players.size(),
	]


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
		banner.text = "Você caiu!\nUm aliado pode te reviver com Vida (W)."


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
