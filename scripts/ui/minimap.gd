# Minimapa (canto inferior direito do HUD): paredes, rotas, fontes, estruturas,
# tropas, monstros e personagens. Cores relativas a quem olha: azul = seu time,
# vermelho = inimigos, amarelo = selva. Botão direito no minimapa: andar até lá.
extends Control

const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const WorldMap = preload("res://scripts/world/world_map.gd")

const MARGIN := 16.0
const MOBA_WIDTH := 300.0
const ARENA_WIDTH := 170.0
const WORLD_WIDTH := 250.0
const NPC_COLOR := Color(1.0, 0.9, 0.3)

const BACKGROUND := Color(0.1, 0.14, 0.1, 0.82)
const BORDER := Color(0.85, 0.8, 0.6, 0.9)
const WALL := Color(0.05, 0.08, 0.05, 0.9)
const LANE := Color(0.55, 0.48, 0.34, 0.75)
const ALLY := Color(0.35, 0.6, 1.0)
const ENEMY := Color(1.0, 0.3, 0.25)
const NEUTRAL := Color(1.0, 0.85, 0.25)
const DEAD := Color(0.35, 0.35, 0.35, 0.8)

var main: Node
var _half := Vector2(20, 20)    # metade do mapa em metros (x, z)
var _scale := 1.0               # pixels por metro


func _ready() -> void:
	if main.get("map_half") != null:
		_half = main.map_half
	var width := ARENA_WIDTH
	if main.get("mode") == "moba":
		width = MOBA_WIDTH
	elif main.get("mode") == "world":
		width = WORLD_WIDTH
	_scale = width / (_half.x * 2.0)
	var map_size := Vector2(width, _half.y * 2.0 * _scale)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -map_size.x - MARGIN
	offset_top = -map_size.y - MARGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


# Metros (x, z do mundo) -> pixels do minimapa. A câmera olha para -Z: z cresce para baixo.
func to_map(world: Vector3) -> Vector2:
	return Vector2(world.x + _half.x, world.z + _half.y) * _scale


func to_world(point: Vector2) -> Vector3:
	var meters := point / _scale - _half
	return Vector3(meters.x, 0.0, meters.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var player: Node = main.get("local_player")
		if is_instance_valid(player):
			player.set_move_target(to_world(event.position))
		accept_event()


func _viewer_team() -> int:
	var player: Node = main.get("local_player")
	return player.team if is_instance_valid(player) else Combat.BLUE


func _color_of(node: Node, my_team: int) -> Color:
	var team := Combat.team_of(node)
	if team == Combat.NEUTRAL:
		return NEUTRAL
	return ALLY if team == my_team else ENEMY


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, BACKGROUND)
	for lane in main.get("map_lanes"):
		draw_rect(_rect_to_map(lane), LANE)
	for wall in main.get("map_walls"):
		draw_rect(_rect_to_map(wall), WALL)
	var my_team := _viewer_team()
	if main.get("mode") == "world":
		draw_circle(to_map(WorldMap.FOUNTAIN), WorldMap.FOUNTAIN_RADIUS * _scale, Color(ALLY, 0.35))
		for npc in [WorldMap.ELDER, WorldMap.MERCHANT]:
			draw_rect(Rect2(to_map(npc) - Vector2(3, 3), Vector2(6, 6)), NPC_COLOR)
	if main.get("mode") == "moba":
		for team in [Combat.BLUE, Combat.RED]:
			var color := ALLY if team == my_team else ENEMY
			draw_circle(to_map(MobaMap.fountain(team)), MobaMap.FOUNTAIN_RADIUS * _scale, Color(color, 0.3))

	var tree := get_tree()
	for structure in tree.get_nodes_in_group("structures"):
		var color := DEAD if structure.health.dead else _color_of(structure, my_team)
		var half_side := 6.0 if structure.kind == "nexus" else 4.0
		var center := to_map(structure.global_position)
		if structure.kind == "inhibitor":
			var diamond := PackedVector2Array([center + Vector2(0, -half_side), center + Vector2(half_side, 0),
				center + Vector2(0, half_side), center + Vector2(-half_side, 0)])
			draw_colored_polygon(diamond, color)
		else:
			draw_rect(Rect2(center - Vector2.ONE * half_side, Vector2.ONE * half_side * 2.0), color)
			draw_rect(Rect2(center - Vector2.ONE * half_side, Vector2.ONE * half_side * 2.0), Color.BLACK, false, 1.0)
	for minion in tree.get_nodes_in_group("minions"):
		if not minion.health.dead:
			draw_circle(to_map(minion.global_position), 1.8, _color_of(minion, my_team).lightened(0.2))
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy.health.dead:
			continue
		var radius := 5.0 if enemy.kind in ["boss", "world_boss", "forest_golem"] else 3.0
		draw_circle(to_map(enemy.global_position), radius, _color_of(enemy, my_team))
		draw_arc(to_map(enemy.global_position), radius, 0.0, TAU, 12, Color.BLACK, 1.0)
	var local: Node = main.get("local_player")
	for player in tree.get_nodes_in_group("players"):
		if player.health.dead:
			continue
		# Assassino invisível do outro time não aparece.
		if player.get("invisible") > 0.0 and player.team != my_team:
			continue
		var point := to_map(player.global_position)
		draw_circle(point, 4.5, _color_of(player, my_team))
		draw_arc(point, 4.5, 0.0, TAU, 16, Color.WHITE if player == local else Color.BLACK, 2.0 if player == local else 1.0)

	_draw_view()
	draw_rect(area, BORDER, false, 2.0)


# Moldura do que a câmera mostra (aproximada pelo zoom).
func _draw_view() -> void:
	var local: Node = main.get("local_player")
	if not is_instance_valid(local):
		return
	var zoom: float = main.get("zoom")
	var view := Vector2(30.0, 17.0) * zoom * (1.25 if main.get("mode") == "moba" else 1.0)
	var center := to_map(local.global_position)
	var rect := Rect2(center - view * _scale / 2.0, view * _scale).intersection(Rect2(Vector2.ZERO, size))
	draw_rect(rect, Color(1, 1, 1, 0.5), false, 1.0)


func _rect_to_map(rect: Rect2) -> Rect2:
	return Rect2((rect.position + _half) * _scale, rect.size * _scale)
