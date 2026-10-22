# Ícones desenhados por código (sem imagens): um símbolo para cada skill e para
# cada elemento, feitos com círculos, linhas e polígonos. draw(canvas, id, ...)
# desenha no CanvasItem (um Control no seu _draw) centrado em `center`.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

const ELEMENT_IDS := {
	E.Type.WATER: "water", E.Type.LIFE: "life", E.Type.SHIELD: "shield", E.Type.COLD: "cold",
	E.Type.LIGHTNING: "lightning", E.Type.ARCANE: "arcane", E.Type.EARTH: "earth", E.Type.FIRE: "fire",
	E.Type.STEAM: "steam", E.Type.ICE: "ice", E.Type.VOID: "void", E.Type.GRAVITY: "gravity",
	E.Type.SMOKE: "smoke", E.Type.BLOOD: "blood",
}


static func element_id(element: int) -> String:
	return ELEMENT_IDS.get(element, "arcane")


# Pontos de um polígono descritos num quadrado de -1 a 1, levados para o ícone.
static func _shape(points: Array, center: Vector2, size: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(center + point * size)
	return result


static func _poly(canvas: CanvasItem, points: Array, center: Vector2, size: float, color: Color) -> void:
	canvas.draw_colored_polygon(_shape(points, center, size), color)


static func _lines(canvas: CanvasItem, points: Array, center: Vector2, size: float, color: Color, width: float) -> void:
	canvas.draw_polyline(_shape(points, center, size), color, width, true)


# `size`: meia largura do ícone em pixels.
static func draw(canvas: CanvasItem, id: String, center: Vector2, size: float, color: Color) -> void:
	var w := maxf(size * 0.14, 2.0)
	var dark := color.darkened(0.55)
	match id:
		# --- Elementos ---
		"water":
			_poly(canvas, [Vector2(0, -0.9), Vector2(0.55, 0.05), Vector2(0.6, 0.35), Vector2(0.35, 0.75),
				Vector2(0, 0.85), Vector2(-0.35, 0.75), Vector2(-0.6, 0.35), Vector2(-0.55, 0.05)], center, size, color)
		"blood":
			_poly(canvas, [Vector2(0, -0.9), Vector2(0.55, 0.05), Vector2(0.6, 0.35), Vector2(0.35, 0.75),
				Vector2(0, 0.85), Vector2(-0.35, 0.75), Vector2(-0.6, 0.35), Vector2(-0.55, 0.05)], center, size, color)
			canvas.draw_circle(center + Vector2(-0.2, 0.3) * size, size * 0.14, color.lightened(0.5))
		"life":
			canvas.draw_rect(Rect2(center - Vector2(0.22, 0.8) * size, Vector2(0.44, 1.6) * size), color)
			canvas.draw_rect(Rect2(center - Vector2(0.8, 0.22) * size, Vector2(1.6, 0.44) * size), color)
		"shield":
			_poly(canvas, [Vector2(-0.7, -0.75), Vector2(0.7, -0.75), Vector2(0.65, 0.1), Vector2(0, 0.85),
				Vector2(-0.65, 0.1)], center, size, color)
			_poly(canvas, [Vector2(-0.4, -0.5), Vector2(0.4, -0.5), Vector2(0.37, 0.05), Vector2(0, 0.5),
				Vector2(-0.37, 0.05)], center, size, dark)
		"cold":
			for i in 3:
				var angle := PI * i / 3.0
				var arm := Vector2(cos(angle), sin(angle)) * size * 0.85
				canvas.draw_line(center - arm, center + arm, color, w)
			canvas.draw_circle(center, size * 0.18, color)
		"ice":
			_poly(canvas, [Vector2(0, -0.9), Vector2(0.45, -0.2), Vector2(0.3, 0.85), Vector2(-0.3, 0.85),
				Vector2(-0.45, -0.2)], center, size, color)
			_lines(canvas, [Vector2(0, -0.9), Vector2(0, 0.85)], center, size, dark, w * 0.6)
		"lightning":
			_poly(canvas, [Vector2(0.15, -0.95), Vector2(-0.55, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.95),
				Vector2(0.55, -0.15), Vector2(0.05, -0.15)], center, size, color)
		"arcane":
			_poly(canvas, [Vector2(0, -0.9), Vector2(0.25, -0.25), Vector2(0.9, 0), Vector2(0.25, 0.25),
				Vector2(0, 0.9), Vector2(-0.25, 0.25), Vector2(-0.9, 0), Vector2(-0.25, -0.25)], center, size, color)
		"earth":
			_poly(canvas, [Vector2(-0.3, -0.75), Vector2(0.45, -0.65), Vector2(0.85, 0.05), Vector2(0.5, 0.7),
				Vector2(-0.35, 0.75), Vector2(-0.85, 0.1)], center, size, color)
			_lines(canvas, [Vector2(-0.3, -0.75), Vector2(0.05, 0.05), Vector2(0.85, 0.05)], center, size, dark, w * 0.6)
			_lines(canvas, [Vector2(0.05, 0.05), Vector2(-0.35, 0.75)], center, size, dark, w * 0.6)
		"fire":
			_poly(canvas, [Vector2(0, -0.95), Vector2(0.3, -0.45), Vector2(0.65, -0.1), Vector2(0.7, 0.35),
				Vector2(0.4, 0.8), Vector2(0, 0.9), Vector2(-0.4, 0.8), Vector2(-0.7, 0.35), Vector2(-0.55, -0.05),
				Vector2(-0.25, 0.15), Vector2(-0.3, -0.4)], center, size, color)
			_poly(canvas, [Vector2(0, -0.2), Vector2(0.3, 0.3), Vector2(0.2, 0.7), Vector2(0, 0.78),
				Vector2(-0.2, 0.7), Vector2(-0.3, 0.3)], center, size, Color(1.0, 0.9, 0.4))
		"steam":
			for row in 3:
				var y := -0.55 + row * 0.55
				_lines(canvas, [Vector2(-0.7, y), Vector2(-0.35, y - 0.2), Vector2(0, y), Vector2(0.35, y - 0.2),
					Vector2(0.7, y)], center, size, color, w)
		"void":
			canvas.draw_circle(center, size * 0.85, color)
			canvas.draw_circle(center, size * 0.45, Color(0.02, 0.0, 0.05))
			canvas.draw_arc(center, size * 0.65, 0.0, TAU, 32, color.lightened(0.4), w * 0.5)
		"gravity":
			for ring in 3:
				canvas.draw_arc(center, size * (0.3 + ring * 0.27), 0.0, TAU, 32, color, w * 0.7)
			canvas.draw_circle(center, size * 0.16, color.lightened(0.5))
		"smoke":
			canvas.draw_circle(center + Vector2(-0.4, 0.15) * size, size * 0.38, color)
			canvas.draw_circle(center + Vector2(0.35, 0.2) * size, size * 0.36, color)
			canvas.draw_circle(center + Vector2(0, -0.2) * size, size * 0.45, color.lightened(0.15))
		# --- Skills ---
		"orb":
			canvas.draw_circle(center, size * 0.55, color)
			canvas.draw_arc(center, size * 0.8, 0.0, TAU, 32, color.lightened(0.3), w * 0.6)
			canvas.draw_circle(center + Vector2(-0.18, -0.18) * size, size * 0.15, Color(1, 1, 1, 0.8))
		"bless_curse":
			canvas.draw_rect(Rect2(center - Vector2(0.16, 0.75) * size, Vector2(0.32, 1.5) * size), color)
			canvas.draw_rect(Rect2(center - Vector2(0.75, 0.16) * size, Vector2(1.5, 0.32) * size), color)
			canvas.draw_arc(center, size * 0.88, 0.0, TAU, 32, color.lightened(0.3), w * 0.5)
		"mini_meteor":
			canvas.draw_circle(center + Vector2(0.25, 0.25) * size, size * 0.42, color)
			for i in 3:
				var start := Vector2(-0.85 + i * 0.25, -0.35 - i * 0.25) * size
				canvas.draw_line(center + start, center + start + Vector2(0.55, 0.55) * size, color.lightened(0.3), w * 0.7)
		"ultimate":
			var star := []
			for i in 10:
				var angle := -PI / 2.0 + TAU * i / 10.0
				var radius := 0.9 if i % 2 == 0 else 0.38
				star.append(Vector2(cos(angle), sin(angle)) * radius)
			_poly(canvas, star, center, size, color)
		"dagger":
			_poly(canvas, [Vector2(0.75, -0.75), Vector2(0.25, 0.05), Vector2(-0.05, -0.25)], center, size, color)
			_lines(canvas, [Vector2(-0.15, -0.35), Vector2(0.35, 0.15)], center, size, color.lightened(0.3), w)
			_lines(canvas, [Vector2(0.1, -0.1), Vector2(-0.6, 0.6)], center, size, color.darkened(0.3), w * 1.2)
		"veil_mark":
			_poly(canvas, [Vector2(-0.9, 0), Vector2(-0.45, -0.4), Vector2(0, -0.5), Vector2(0.45, -0.4),
				Vector2(0.9, 0), Vector2(0.45, 0.4), Vector2(0, 0.5), Vector2(-0.45, 0.4)], center, size, color)
			canvas.draw_circle(center, size * 0.28, dark)
		"shadow_step":
			_poly(canvas, [Vector2(-0.2, -0.6), Vector2(0.8, 0), Vector2(-0.2, 0.6), Vector2(0.05, 0)], center, size, color)
			for i in 2:
				var x := -0.85 + i * 0.3
				_lines(canvas, [Vector2(x, -0.35), Vector2(x, 0.35)], center, size, color.darkened(0.2 + 0.25 * i), w)
		"whirl":
			canvas.draw_arc(center, size * 0.7, 0.3, PI * 1.6, 24, color, w * 1.2)
			_poly(canvas, [Vector2(0.75, -0.55), Vector2(0.95, 0.05), Vector2(0.35, -0.05)], center, size, color)
			canvas.draw_arc(center, size * 0.3, PI, PI * 2.6, 16, color.lightened(0.2), w * 0.8)
		"shout":
			_poly(canvas, [Vector2(-0.8, -0.25), Vector2(-0.35, -0.25), Vector2(0.05, -0.6), Vector2(0.05, 0.6),
				Vector2(-0.35, 0.25), Vector2(-0.8, 0.25)], center, size, color)
			for ring in 2:
				canvas.draw_arc(center + Vector2(0.1, 0) * size, size * (0.45 + ring * 0.3), -0.7, 0.7, 12, color, w * 0.7)
		"charge":
			for i in 2:
				var x := -0.55 + i * 0.6
				_lines(canvas, [Vector2(x, -0.6), Vector2(x + 0.45, 0), Vector2(x, 0.6)], center, size, color, w * 1.3)
		_:
			canvas.draw_circle(center, size * 0.5, color)
