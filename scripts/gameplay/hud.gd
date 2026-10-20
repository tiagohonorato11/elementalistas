# HUD: fila de elementos, forma do feitiço, vida do mago e ajuda de controles.
extends CanvasLayer

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")

const HELP := """Elementos: Q Água | W Vida | E Escudo | R Frio | A Raio | S Arcano | D Terra | F Fogo
Andar: segurar botão esquerdo (ou setas) | Lançar à frente: botão direito (segure para spray/beam/arco)
Área: Shift + botão direito | Em si mesmo: botão do meio ou Espaço | Esc: sair para o lobby"""

var player: Node
var status_label: Label


func _ready() -> void:
	status_label = _make_label(Vector2(16, 16), 26)
	_make_label(Vector2(16, 630), 16).text = HELP


func _process(_delta: float) -> void:
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


func _make_label(at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label
