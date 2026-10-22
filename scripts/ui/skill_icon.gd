# Ícone desenhado do HUD (sem imagens), em três formatos:
# - "skill": quadrado da skill (Q W E R): símbolo, tecla, nome e custo; a recarga
#   escurece o ícone como um relógio; dourado pulsando quando a carga gera MEGA;
#   pisca em vermelho quando a skill é negada; barra embaixo ao segurar.
# - "slot": círculo de um elemento da carga (vazio: só o contorno).
# - "legend": tecla D/F/G com o símbolo e o nome do elemento.
# A dica (tooltip_text) é montada pelo HUD.
extends Control

const Glyphs = preload("res://scripts/ui/glyphs.gd")

const BLINK_TIME := 450         # ms do piscar vermelho
const READY_BG := Color(0.2, 0.18, 0.36)
const NO_MANA_BG := Color(0.12, 0.17, 0.38)
const DISABLED_BG := Color(0.13, 0.13, 0.16)
const GOLD := Color(1.0, 0.8, 0.25)

var mode := "skill"
var glyph := ""
var glyph_color := Color.WHITE
var key_text := ""
var title := ""
var detail := ""
var state := "ready"            # ready / cooldown / nomana / silenced
var cooldown_ratio := 0.0       # fração da recarga que ainda falta (0 a 1)
var mega := false
var hold := 0.0                 # 0 a 1 enquanto segura (W do Mago)
var denied_at := -100000
var filled := true              # "slot": tem elemento?
var _shown := ""


# Atualiza e só redesenha se algo mudou (ou se está animando).
func set_view(values: Dictionary) -> void:
	for key in values:
		set(key, values[key])
	var key := str([glyph, glyph_color, key_text, title, detail, state, snappedf(cooldown_ratio, 0.01),
		mega, snappedf(hold, 0.02), denied_at, filled])
	if key != _shown or mega or _blinking():
		_shown = key
		queue_redraw()


func _blinking() -> bool:
	return Time.get_ticks_msec() - denied_at < BLINK_TIME


func _process(_delta: float) -> void:
	if mega or _blinking():
		queue_redraw()


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(text: String, at: Vector2, width: float, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string_outline(_font(), at, text, align, width, size, 4, Color(0, 0, 0, 0.9))
	draw_string(_font(), at, text, align, width, size, color)


func _draw() -> void:
	match mode:
		"skill":
			_draw_skill()
		"slot":
			_draw_slot()
		"legend":
			_draw_legend()


func _box(color: Color, border: Color, border_width: int, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	draw_style_box(style, Rect2(Vector2.ZERO, size))


func _draw_skill() -> void:
	var background := READY_BG
	if state == "nomana":
		background = NO_MANA_BG
	elif state != "ready":
		background = DISABLED_BG
	var border := Color(1, 1, 1, 0.35)
	var border_width := 2
	if mega:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		border = GOLD.lerp(Color.WHITE, pulse * 0.3)
		border_width = 4
		background = background.lerp(GOLD.darkened(0.6), 0.35 * pulse)
	if _blinking():
		border = Color(1.0, 0.2, 0.2)
		border_width = 4
	_box(background, border, border_width, 10)

	var center := Vector2(size.x / 2.0, size.y * 0.4)
	var icon_size := minf(size.x, size.y) * 0.25
	var color := glyph_color if state == "ready" or state == "nomana" else glyph_color.darkened(0.5)
	Glyphs.draw(self, glyph, center, icon_size, color)
	# Recarga: sombra em forma de relógio, do topo no sentido horário.
	if cooldown_ratio > 0.0:
		var points := PackedVector2Array([center])
		var steps := 24
		for i in steps + 1:
			var angle := -PI / 2.0 + TAU * cooldown_ratio * i / steps
			points.append(center + Vector2(cos(angle), sin(angle)) * icon_size * 1.5)
		draw_colored_polygon(points, Color(0, 0, 0, 0.55))

	_text(key_text, Vector2(6, 17), 30, 15, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	if mega:
		_text("MEGA", Vector2(0, 15), size.x - 6, 12, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# Nome longo (ex.: "Tempestade suprema"): letra menor para caber.
	var title_size := 12
	while title_size > 8 and _font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > size.x - 6:
		title_size -= 1
	_text(title, Vector2(0, size.y - 20), size.x, title_size, Color.WHITE)
	_text(detail, Vector2(0, size.y - 6), size.x, 12, Color(0.8, 0.85, 1.0))
	if hold > 0.0:
		draw_rect(Rect2(Vector2(4, size.y - 4), Vector2((size.x - 8) * hold, 3)), GOLD)


func _draw_slot() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 2.0
	if not filled:
		draw_circle(center, radius, Color(0.2, 0.2, 0.25, 0.25))
		draw_arc(center, radius, 0.0, TAU, 32, Color(1, 1, 1, 0.3), 2.0, true)
		return
	draw_circle(center, radius, glyph_color.darkened(0.15))
	draw_arc(center, radius, 0.0, TAU, 32, glyph_color.lightened(0.45), 3.0, true)
	Glyphs.draw(self, glyph, center, radius * 0.6, Color(1, 1, 1, 0.95))


func _draw_legend() -> void:
	_box(glyph_color.darkened(0.2), glyph_color.lightened(0.4), 2, 8)
	Glyphs.draw(self, glyph, Vector2(size.y * 0.5 + 18, size.y / 2.0), size.y * 0.3, Color(1, 1, 1, 0.95))
	_text(key_text, Vector2(6, size.y / 2.0 + 5), 20, 14, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	_text(title, Vector2(size.y * 0.5 + 30, size.y / 2.0 + 5), size.x - size.y * 0.5 - 32, 13, Color.WHITE,
		HORIZONTAL_ALIGNMENT_LEFT)
