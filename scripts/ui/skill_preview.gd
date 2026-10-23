# Prévia animada de uma skill (Grimório de combos): uma arena vista de cima,
# desenhada por código, com você à esquerda, um aliado e três bonecos inimigos.
# A skill se repete em loop com as cores e as zonas da carga. É ilustrativa:
# as distâncias seguem os números das classes, mas não é a simulação do jogo.
extends Control

const E = preload("res://scripts/core/elements.gd")
const Glyphs = preload("res://scripts/ui/glyphs.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const LOOP := 3.2               # s de cada repetição
const METERS := 22.0            # metros de largura visíveis
const GROUND := Color(0.13, 0.15, 0.13)
const GRID := Color(1, 1, 1, 0.04)
const PLAYER_COLOR := Color(0.35, 0.75, 1.0)
const ALLY_COLOR := Color(0.4, 1.0, 0.6)
const ENEMY_COLOR := Color(1.0, 0.35, 0.3)
const GOLD := Color(1.0, 0.8, 0.25)

# Onde cada ultimate acontece e como aparece: "cursor" (nos inimigos), "self"
# (em volta de você) ou "front" (onda à frente).
const ULTIMATE_SHAPES := {
	"meteor": {"at": "cursor", "radius": 4.0, "style": "fall"},
	"storm": {"at": "self", "radius": 9.0, "style": "bolts"},
	"frost": {"at": "self", "radius": 10.0, "style": "ring"},
	"blessing": {"at": "team", "radius": 5.0, "style": "heal"},
	"quake": {"at": "self", "radius": 7.0, "style": "ring"},
	"cataclysm": {"at": "cursor", "radius": 5.0, "style": "burst"},
	"tide": {"at": "front", "radius": 4.0, "style": "wave"},
	"fortress": {"at": "team", "radius": 4.0, "style": "walls"},
	"eclipse": {"at": "self", "radius": 9.0, "style": "ring"},
	"singularity": {"at": "cursor", "radius": 5.0, "style": "pull"},
	"smokescreen": {"at": "self", "radius": 8.0, "style": "cloud"},
	"blood_moon": {"at": "self", "radius": 9.0, "style": "drain"},
	"mega_fire": {"at": "cursor", "radius": 6.0, "style": "rain"},
	"mega_lightning": {"at": "self", "radius": 11.0, "style": "bolts"},
	"mega_cold": {"at": "self", "radius": 15.0, "style": "ring"},
	"mega_life": {"at": "team", "radius": 6.0, "style": "heal"},
	"mega_earth": {"at": "front", "radius": 2.5, "style": "crack"},
	"mega_arcane": {"at": "self", "radius": 8.0, "style": "burst"},
	"mega_water": {"at": "front", "radius": 7.0, "style": "wave"},
	"mega_shield": {"at": "team", "radius": 5.0, "style": "walls"},
	"mega_void": {"at": "self", "radius": 12.0, "style": "ring"},
	"mega_gravity": {"at": "cursor", "radius": 6.0, "style": "pull"},
	"mega_smoke": {"at": "self", "radius": 12.0, "style": "cloud"},
	"mega_blood": {"at": "self", "radius": 10.0, "style": "drain"},
}

var skill: Dictionary = {}
var charge: Array = []
var time := 0.0


func show_skill(new_skill: Dictionary, new_charge: Array) -> void:
	skill = new_skill
	charge = new_charge.duplicate()
	time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	time = fmod(time + delta, LOOP)
	queue_redraw()


# --- Coordenadas: metros (x para a direita, y para baixo) -> pixels ---

func _scale() -> float:
	return size.x / METERS


func _p(meters: Vector2) -> Vector2:
	return Vector2(size.x * 0.14, size.y * 0.5) + meters * _scale()


func _me() -> Vector2:
	return Vector2.ZERO


func _ally() -> Vector2:
	return Vector2(-1.2, 2.6)


func _enemies() -> Array:
	return [Vector2(10.5, -1.6), Vector2(12.0, 0.4), Vector2(10.2, 1.9)]


func _target() -> Vector2:
	return Vector2(11.0, 0.2)


func _color() -> Color:
	return Vfx.mix_color(charge).lightened(0.15) if not charge.is_empty() else Color(0.85, 0.85, 1.0)


# 0 a 1 entre `from` e `to` segundos do loop.
func _phase(from: float, to: float) -> float:
	return clampf((time - from) / (to - from), 0.0, 1.0)


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var width := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	at.x -= width / 2.0
	draw_string_outline(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- Desenho ---

func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = GROUND
	style.set_corner_radius_all(10)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(2)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var step := _scale() * 2.0
	var x := fmod(_p(Vector2.ZERO).x, step)
	while x < size.x:
		draw_line(Vector2(x, 4), Vector2(x, size.y - 4), GRID)
		x += step
	var y := fmod(_p(Vector2.ZERO).y, step)
	while y < size.y:
		draw_line(Vector2(4, y), Vector2(size.x - 4, y), GRID)
		y += step
	if skill.is_empty():
		return
	match skill.id:
		"orb":
			_draw_orb()
		"bless_curse":
			_draw_bless_curse()
		"mini_meteor":
			_draw_meteor_skill()
		"ultimate":
			_draw_ultimate()
		"dagger":
			_draw_dagger()
		"veil_mark":
			_draw_veil_mark()
		"shadow_step":
			_draw_shadow_step()
		"whirl":
			_draw_whirl()
		"shout":
			_draw_shout()
		"charge":
			_draw_charge()
	_draw_charge_badge()


# Personagem visto de cima: círculo com contorno e um tracinho para onde olha.
func _unit(at: Vector2, color: Color, label := "", alpha := 1.0, facing := Vector2.RIGHT, hit := 0.0) -> void:
	var center := _p(at)
	var radius := _scale() * 0.55
	var body := color.darkened(0.35)
	if hit > 0.0:
		body = body.lerp(_color(), hit)
	body.a = alpha
	draw_circle(center + Vector2(2, 3), radius, Color(0, 0, 0, 0.3 * alpha))
	draw_circle(center, radius, body)
	draw_arc(center, radius, 0.0, TAU, 24, Color(color, alpha), 2.0, true)
	draw_line(center, center + facing * radius * 1.3, Color(color.lightened(0.4), alpha), 3.0)
	if not label.is_empty():
		_text(label, center + Vector2(0, radius + 14), 11, Color(1, 1, 1, 0.7 * alpha))


# Inimigos; `hit(i)` diz quanto cada um está sendo atingido (0 a 1).
func _draw_enemies(hit: Callable, offsets := []) -> void:
	var list := _enemies()
	for i in list.size():
		var at: Vector2 = list[i]
		if i < offsets.size():
			at += offsets[i]
		_unit(at, ENEMY_COLOR, "inimigo" if i == 1 else "", 1.0, Vector2.LEFT, hit.call(i))


func _no_hit(_i: int) -> float:
	return 0.0


# Fatias coloridas da carga num anel (um setor por elemento).
func _charge_ring(center: Vector2, radius: float, alpha: float, width := 4.0) -> void:
	if charge.is_empty():
		draw_arc(center, radius, 0.0, TAU, 48, Color(_color(), alpha), width, true)
		return
	var part := TAU / charge.size()
	for i in charge.size():
		var color: Color = E.COLORS[charge[i]]
		draw_arc(center, radius, part * i + time, part * (i + 1) + time, 24, Color(color, alpha), width, true)


func _disc(center: Vector2, radius: float, alpha: float) -> void:
	draw_circle(center, radius, Color(_color(), 0.22 * alpha))
	_charge_ring(center, radius, alpha)


# Zonas que ficam no chão, uma por elemento (Mini meteoro e ultimates).
func _zones(elements: Array, at: Vector2, radius: float, alpha: float) -> void:
	var seen: Array = []
	for element in elements:
		if not (element in seen):
			seen.append(element)
	for i in seen.size():
		var color: Color = E.COLORS[seen[i]]
		var pulse := 0.5 + 0.5 * sin(time * 6.0 + i)
		var center := _p(at) + Vector2.from_angle(TAU * i / seen.size() + 0.4) * (radius * 0.35 if seen.size() > 1 else 0.0)
		draw_circle(center, radius * 0.65, Color(color, (0.16 + 0.08 * pulse) * alpha))
		draw_arc(center, radius * 0.65, 0.0, TAU, 32, Color(color, 0.6 * alpha), 2.0, true)
		Glyphs.draw(self, Glyphs.element_id(seen[i]), center, radius * 0.18, Color(color.lightened(0.3), 0.9 * alpha))


func _sparks(center: Vector2, radius: float, amount: int, alpha: float) -> void:
	for i in amount:
		var angle := TAU * i / amount + time * 2.0
		var element: int = charge[i % charge.size()] if not charge.is_empty() else E.Type.ARCANE
		draw_circle(center + Vector2.from_angle(angle) * radius, 3.0, Color(E.COLORS[element].lightened(0.3), alpha))


func _bolt(from: Vector2, to: Vector2, color: Color, seed_value: int) -> void:
	var points := PackedVector2Array([from])
	var random := RandomNumberGenerator.new()
	random.seed = seed_value + int(time * 12.0)
	for i in range(1, 6):
		var point := from.lerp(to, i / 6.0)
		points.append(point + Vector2(random.randf_range(-8, 8), random.randf_range(-8, 8)))
	points.append(to)
	draw_polyline(points, color, 3.0, true)
	draw_polyline(points, Color(1, 1, 1, 0.8), 1.0, true)


# Círculos D F G da carga no canto, para lembrar o que está sendo mostrado.
func _draw_charge_badge() -> void:
	var radius := 11.0
	for i in charge.size():
		var center := Vector2(18 + i * 26, 18)
		draw_circle(center, radius, E.COLORS[charge[i]].darkened(0.15))
		Glyphs.draw(self, Glyphs.element_id(charge[i]), center, radius * 0.6, Color.WHITE)


# --- Skills do Mago ---

func _draw_orb() -> void:
	var target := _target()
	var travel := _phase(0.2, 1.0)
	var boom := _phase(1.0, 1.7)
	var radius := Projectile.splash_radius_for(charge) if not charge.is_empty() else 0.0
	var hit := func(i: int) -> float:
		var close: bool = i == 1 or radius >= (_enemies()[i] - target).length()
		return (1.0 - boom) if close and boom > 0.0 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit)
	_unit(_me(), PLAYER_COLOR, "você")
	if travel > 0.0 and travel < 1.0:
		var at := _p(_me().lerp(target, travel))
		var orb_radius := _scale() * (0.35 + 0.15 * charge.size())
		for i in 4:
			draw_circle(at - Vector2(i * 10, 0), orb_radius * (1.0 - i * 0.2), Color(_color(), 0.25))
		draw_circle(at, orb_radius, _color())
		draw_circle(at - Vector2(orb_radius, orb_radius) * 0.3, orb_radius * 0.3, Color(1, 1, 1, 0.7))
	if boom > 0.0 and boom < 1.0 and radius > 0.0:
		_disc(_p(target), radius * _scale() * (0.4 + 0.6 * boom), 1.0 - boom)
		_text("área %.1f m" % radius, _p(target) + Vector2(0, -radius * _scale() - 8), 13, Color.WHITE)


func _draw_bless_curse() -> void:
	# 0-1 s: bênção no aliado; 1-2 s: maldição no inimigo; 2-3,2 s: bolha (segurando).
	var bless := _phase(0.1, 1.0)
	var curse := _phase(1.1, 2.0)
	var bubble := _phase(2.1, 3.1)
	var hit := func(i: int) -> float:
		return 0.7 if i == 1 and curse > 0.0 and curse < 1.0 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado", 1.0, Vector2.RIGHT, 0.6 if bless > 0.0 and bless < 1.0 else 0.0)
	_draw_enemies(hit)
	_unit(_me(), PLAYER_COLOR, "você")
	if bless > 0.0 and bless < 1.0:
		var center := _p(_ally())
		_charge_ring(center, _scale() * (0.7 + 0.5 * bless), 1.0 - bless)
		_sparks(center, _scale() * 0.9, 6, 1.0 - bless)
		_text("Bênção: cura + proteção", center + Vector2(0, -_scale() * 1.4), 13, ALLY_COLOR.lightened(0.3))
	if curse > 0.0 and curse < 1.0:
		var center := _p(_enemies()[1])
		_charge_ring(center, _scale() * (1.3 - 0.5 * curse), 1.0)
		_text("Maldição: lento + vulnerável", center + Vector2(0, -_scale() * 1.5), 13, ENEMY_COLOR.lightened(0.3))
	if bubble > 0.0:
		var center := _p(_me())
		var radius: float = skill.get("bubble_radius", 3.0) * _scale() * minf(bubble * 3.0, 1.0)
		draw_circle(center, radius, Color(_color(), 0.18))
		_charge_ring(center, radius, 0.9, 3.0)
		draw_rect(Rect2(center + Vector2(-30, 30), Vector2(60 * minf(bubble * 3.0, 1.0), 4)), GOLD)
		_text("Segurou: bolha de escudo", center + Vector2(0, -radius - 8), 13, GOLD)


func _draw_meteor_skill() -> void:
	var target := _target()
	var fall := _phase(0.2, 0.9)
	var zone := _phase(0.9, 3.1)
	var radius: float = skill.get("radius", 3.5)
	var hit := func(i: int) -> float:
		return 1.0 - _phase(0.9, 1.4) if fall >= 1.0 and (_enemies()[i] - target).length() <= radius else 0.0
	if zone > 0.0 and not charge.is_empty():
		_zones(charge, target, radius * _scale(), 1.0 - _phase(2.6, 3.1))
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit)
	_unit(_me(), PLAYER_COLOR, "você")
	if fall < 1.0:
		draw_arc(_p(target), radius * _scale(), 0.0, TAU, 40, Color(1, 1, 1, 0.3), 2.0, true)
	if fall > 0.0 and fall < 1.0:
		var start := target + Vector2(-5, -7)
		var at := _p(start.lerp(target, fall))
		for i in 4:
			draw_circle(at - Vector2(-5, -7).normalized() * i * 9.0, _scale() * (0.6 - i * 0.1), Color(_color(), 0.3))
		draw_circle(at, _scale() * 0.6, _color())
	if fall >= 1.0 and zone < 0.25:
		_disc(_p(target), radius * _scale() * (0.5 + 2.0 * zone), 1.0 - zone * 4.0)
	if zone > 0.0 and not charge.is_empty():
		_text("zona de %d s" % roundi(skill.get("zone_time", 3.0)), _p(target) + Vector2(0, radius * _scale() + 16),
			13, Color.WHITE)


func _draw_ultimate() -> void:
	var id := Ultimates.resolve(charge)
	if id.is_empty():
		_unit(_ally(), ALLY_COLOR, "aliado")
		_draw_enemies(_no_hit)
		_unit(_me(), PLAYER_COLOR, "você")
		_text("Carregue elementos para ver o ultimate", size / 2.0, 15, Color.WHITE)
		return
	var shape: Dictionary = ULTIMATE_SHAPES.get(id, {"at": "cursor", "radius": 4.0, "style": "burst"})
	var mega := Ultimates.is_mega(charge)
	var color := GOLD if mega else _color()
	var radius: float = shape.radius
	var center := _target()
	match shape.at:
		"self":
			center = _me()
		"team":
			center = _me().lerp(_ally(), 0.5)
		"front":
			center = _me() + Vector2(2, 0)
	var go := _phase(0.3, 1.3)
	var fade := 1.0 - _phase(2.4, 3.1)
	var reach := func(i: int) -> bool:
		var enemy: Vector2 = _enemies()[i]
		if shape.at == "front":
			return go * 12.0 + 2.0 >= enemy.x and absf(enemy.y) <= radius + 1.0
		return (enemy - center).length() <= radius + 0.6
	var hit := func(i: int) -> float:
		return 0.8 * fade if go > 0.6 and reach.call(i) else 0.0
	var offsets := []
	if shape.style == "pull" or shape.style == "wave":
		for enemy in _enemies():
			var move: Vector2 = (_target() - enemy) * 0.6 if shape.style == "pull" else Vector2(3.0, 0)
			offsets.append(move * _phase(0.6, 1.6))
	var zones := Ultimates.zone_elements(charge)
	if not zones.is_empty() and go >= 1.0:
		_zones(zones, _target() if shape.at == "cursor" else center, 2.5 * _scale(), fade)
	_unit(_ally(), ALLY_COLOR, "aliado", 1.0, Vector2.RIGHT,
		0.7 * fade if go > 0.5 and (shape.at == "team" or shape.style == "cloud") else 0.0)
	_draw_enemies(hit, offsets)
	_unit(_me(), PLAYER_COLOR, "você")
	var pixels := radius * _scale()
	var at := _p(center)
	match shape.style:
		"fall", "rain":
			var count := 5 if shape.style == "rain" else 1
			for i in count:
				var spot := center + (Vector2.from_angle(TAU * i / count) * radius * 0.5 if count > 1 else Vector2.ZERO)
				var fall := _phase(0.2 + i * 0.12, 0.9 + i * 0.12)
				if fall < 1.0:
					var start := spot + Vector2(-4, -6)
					draw_circle(_p(start.lerp(spot, fall)), _scale() * (0.9 if count == 1 else 0.6), color)
				elif fade > 0.0:
					_disc(_p(spot), pixels * (0.45 if count > 1 else 1.0), fade)
		"bolts":
			if go > 0.0:
				draw_arc(at, pixels, 0.0, TAU, 48, Color(color, 0.25 * fade), 2.0, true)
				for i in _enemies().size():
					if reach.call(i) and fmod(time * 5.0 + i, 1.0) < 0.5 and fade > 0.0:
						var enemy := _p(_enemies()[i])
						_bolt(enemy + Vector2(0, -size.y * 0.4), enemy, color, i)
		"ring", "drain":
			if go > 0.0:
				var grow := pixels * go
				draw_circle(at, grow, Color(color, 0.12 * fade))
				_charge_ring(at, grow, fade, 5.0)
				if shape.style == "drain" and go >= 1.0:
					for i in _enemies().size():
						if reach.call(i):
							var from := _p(_enemies()[i])
							var dot := from.lerp(at, fmod(time * 1.5 + i * 0.3, 1.0))
							draw_circle(dot, 4.0, Color(E.COLORS[E.Type.BLOOD].lightened(0.3), fade))
		"burst":
			var charge_up := _phase(0.2, 1.1)
			if charge_up < 1.0:
				draw_circle(at, pixels * 0.25 * charge_up, Color(color, 0.7))
				_charge_ring(at, pixels * (1.0 - charge_up), 0.6)
			elif fade > 0.0:
				_disc(at, pixels * minf(1.0, 0.4 + _phase(1.1, 1.4)), fade)
				_sparks(at, pixels * 0.8, 10, fade)
		"pull":
			if go > 0.0:
				for ring in 3:
					var r := pixels * fmod(1.0 - time * 0.8 + ring / 3.0, 1.0)
					draw_arc(at, r, 0.0, TAU, 40, Color(color, 0.5 * fade), 3.0, true)
				draw_circle(at, _scale() * 0.6, Color(0.02, 0.0, 0.05, fade))
		"wave":
			if go > 0.0 and fade > 0.0:
				var front_x := _p(center + Vector2(go * 12.0, 0)).x
				var half := pixels
				draw_rect(Rect2(Vector2(front_x - 24, at.y - half), Vector2(24, half * 2)), Color(color, 0.45 * fade))
				draw_line(Vector2(front_x, at.y - half), Vector2(front_x, at.y + half), Color(1, 1, 1, 0.7 * fade), 3.0)
		"crack":
			if go > 0.0 and fade > 0.0:
				var end := _p(center + Vector2(go * 12.0, 0))
				_bolt(at, end, color.darkened(0.2), 7)
				for i in int(go * 4.0):
					var wall := _p(center + Vector2(2.5 + i * 2.5, 0))
					draw_rect(Rect2(wall + Vector2(-6, -_scale() * 2.5), Vector2(12, 14)), Color(0.55, 0.4, 0.25, fade))
					draw_rect(Rect2(wall + Vector2(-6, _scale() * 2.5 - 14), Vector2(12, 14)), Color(0.55, 0.4, 0.25, fade))
		"heal":
			if go > 0.0:
				_disc(at, pixels * go, fade)
				_sparks(_p(_ally()), _scale(), 6, fade)
				_sparks(_p(_me()), _scale(), 6, fade)
		"walls":
			if go > 0.0:
				for i in 8:
					var spot := at + Vector2.from_angle(TAU * i / 8.0) * pixels * go
					draw_rect(Rect2(spot - Vector2(7, 7), Vector2(14, 14)), Color(color, fade))
				_charge_ring(_p(_me()), _scale() * 0.9, fade)
				_charge_ring(_p(_ally()), _scale() * 0.9, fade)
		"cloud":
			if go > 0.0:
				for i in 9:
					var spot := at + Vector2.from_angle(TAU * i / 9.0 + time * 0.3) * pixels * 0.6 * go
					draw_circle(spot, pixels * 0.35, Color(0.5, 0.5, 0.52, 0.28 * fade))
	_text(("MEGA  " if mega else "") + Ultimates.label(id), Vector2(size.x / 2.0, 26), 18, color.lightened(0.2))


# --- Skills do Assassino ---

func _draw_dagger() -> void:
	var target: Vector2 = _enemies()[1]
	var travel := _phase(0.2, 0.7)
	var hit := func(i: int) -> float:
		return 1.0 - _phase(0.7, 1.3) if i == 1 and travel >= 1.0 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit)
	_unit(_me(), PLAYER_COLOR, "você")
	if travel > 0.0 and travel < 1.0:
		var at := _p(_me().lerp(target, travel))
		draw_line(at - Vector2(_scale() * 2.0, 0), at, Color(_color(), 0.35), 4.0)
		draw_colored_polygon(PackedVector2Array([at + Vector2(10, 0), at + Vector2(-8, -4), at + Vector2(-8, 4)]),
			_color().lightened(0.3))
	if travel >= 1.0 and time < 1.6:
		_charge_ring(_p(target), _scale() * 0.9, 1.0 - _phase(0.7, 1.6))
		_text("pelas costas: 2x", _p(target) + Vector2(0, -_scale() * 1.3), 13, GOLD)


func _draw_veil_mark() -> void:
	var veil := _phase(0.2, 1.4)
	var mark := _phase(1.6, 2.4)
	var hit := func(i: int) -> float:
		return 0.6 if i == 1 and mark > 0.0 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit)
	var alpha := 1.0 - 0.75 * minf(veil * 3.0, 1.0) if time < 1.6 else 1.0
	_unit(_me(), PLAYER_COLOR, "você", alpha)
	if veil > 0.0 and time < 1.6:
		_charge_ring(_p(_me()), _scale() * 1.0, 0.5)
		_text("Véu: invisível %.1f s" % skill.get("invisible", 2.5), _p(_me()) + Vector2(0, -_scale() * 1.4), 13,
			Color.WHITE)
	if mark > 0.0:
		var center := _p(_enemies()[1])
		var r := _scale() * (1.6 - 0.6 * mark)
		draw_arc(center, r, 0.0, TAU, 32, Color(GOLD, 0.9), 2.0, true)
		for i in 4:
			var dir := Vector2.from_angle(PI / 2.0 * i)
			draw_line(center + dir * r * 0.6, center + dir * r * 1.2, GOLD, 2.0)
		_text("Marca: +%d%% de dano" % roundi(skill.get("vulnerable", 0.3) * 100.0), center + Vector2(0, -r - 8),
			13, GOLD)


func _draw_shadow_step() -> void:
	var distance: float = skill.get("distance", 6.0)
	var land := Vector2(distance, 0)
	var jump := _phase(0.3, 0.6)
	var burst := _phase(0.6, 1.4)
	var radius: float = skill.get("radius", 2.5)
	var offsets := [Vector2(-4.0, 0), Vector2(-4.3, 0), Vector2(-4.0, 0)]   # inimigos mais perto
	var hit := func(i: int) -> float:
		var enemy: Vector2 = _enemies()[i] + offsets[i]
		return 1.0 - burst if burst > 0.0 and (enemy - land).length() <= radius + 0.6 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit, offsets)
	var at := _me().lerp(land, jump)
	if jump > 0.0:
		for i in 3:
			_unit(_me().lerp(at, i / 3.0), PLAYER_COLOR, "", 0.15 + 0.1 * i)
	_unit(at, PLAYER_COLOR, "você")
	if burst > 0.0 and burst < 1.0:
		_disc(_p(land), radius * _scale() * (0.4 + 0.6 * burst), 1.0 - burst)
	if jump < 1.0:
		draw_arc(_p(land), radius * _scale(), 0.0, TAU, 32, Color(1, 1, 1, 0.25), 2.0, true)
	_text("salto de %d m" % roundi(distance), _p(Vector2(distance / 2.0, -2.2)), 13, Color(1, 1, 1, 0.8))


# --- Skills do Lutador ---

func _draw_whirl() -> void:
	var radius: float = skill.get("radius", 2.8)
	var spin := _phase(0.3, 1.1)
	var offsets := []
	for enemy in _enemies():
		offsets.append(Vector2(-7.5, 0) + Vector2((enemy - _target()).x * 0.4, (enemy - _target()).y * 0.6))
	var push := _phase(0.8, 1.4)
	for i in offsets.size():
		offsets[i] += (_enemies()[i] + offsets[i]).normalized() * 2.0 * push
	var hit := func(i: int) -> float:
		return 1.0 - _phase(0.8, 1.8) if spin > 0.6 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit, offsets)
	var facing := Vector2.from_angle(spin * TAU * 2.0) if spin > 0.0 and spin < 1.0 else Vector2.RIGHT
	_unit(_me(), PLAYER_COLOR, "você", 1.0, facing)
	if spin > 0.0 and spin < 1.0:
		var center := _p(_me())
		var start := spin * TAU * 2.0
		draw_arc(center, radius * _scale(), start, start + PI * 1.2, 24, Color(_color(), 0.8), 8.0, true)
		_charge_ring(center, radius * _scale(), 0.4, 2.0)
	if spin >= 1.0 and time < 1.8:
		_text("empurra", _p(Vector2(3.5, -2.0)), 13, Color.WHITE)


func _draw_shout() -> void:
	# 0-1,4 s: Grito no aliado (cura, rápido, forte); 1,6-3 s: Desafio no inimigo.
	var shout := _phase(0.2, 1.4)
	var dare := _phase(1.6, 2.8)
	var hit := func(i: int) -> float:
		return 0.6 if i == 1 and dare > 0.3 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado", 1.0, Vector2.RIGHT, 0.6 if shout > 0.3 and shout < 1.0 else 0.0)
	_draw_enemies(hit)
	_unit(_me(), PLAYER_COLOR, "você")
	if shout > 0.0 and shout < 1.0:
		for ring in 3:
			var r := _scale() * (1.0 + fmod(shout * 3.0 + ring * 0.33, 1.0) * 3.0)
			draw_arc(_p(_me()), r, -1.2 + PI / 2.0, 1.2 + PI / 2.0, 20, Color(_color(), 1.0 - shout), 3.0, true)
		_text("Grito: cura, +%d%% velocidade" % roundi(skill.get("haste", 0.3) * 100.0),
			_p(_ally()) + Vector2(0, _scale() * 2.0), 13, ALLY_COLOR.lightened(0.3))
	if dare > 0.0 and dare < 1.0:
		var from := _p(_me())
		var to := _p(_enemies()[1])
		for ring in 3:
			var at := from.lerp(to, fmod(dare * 2.0 + ring * 0.33, 1.0))
			draw_arc(at, _scale() * 0.8, -0.8, 0.8, 12, Color(_color(), 0.9), 3.0, true)
		_charge_ring(to, _scale() * 1.1, 1.0 - dare)
		_text("Desafio: lento + carga", to + Vector2(0, -_scale() * 1.5), 13, ENEMY_COLOR.lightened(0.3))


func _draw_charge() -> void:
	var run := _phase(0.3, 0.9)
	var length := 7.0
	var offsets := [Vector2(-4.0, -0.4), Vector2(-4.0, -0.4), Vector2(-4.0, 0.5)]   # na linha da corrida
	var push := _phase(0.75, 1.2)
	offsets[0] += Vector2(0.5, -2.0) * push
	offsets[1] += Vector2(1.5, 1.8) * push
	var hit := func(i: int) -> float:
		return 1.0 - _phase(0.8, 1.6) if run > 0.7 and i < 2 else 0.0
	_unit(_ally(), ALLY_COLOR, "aliado")
	_draw_enemies(hit, offsets)
	var at := _me().lerp(Vector2(length, 0), run)
	if run > 0.0:
		draw_line(_p(_me()), _p(at), Color(_color(), 0.35), _scale() * 1.2)
		_charge_ring(_p(at), _scale() * 0.8, 0.8)
	_unit(at, PLAYER_COLOR, "você")
	_text("investida de %d m" % roundi(length), _p(Vector2(length / 2.0, -2.2)), 13, Color(1, 1, 1, 0.8))
