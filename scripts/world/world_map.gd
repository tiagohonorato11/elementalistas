# Mapa do modo Mundo (RPG), desenho original e pequeno, para crescer depois.
#
#           x = -48 ............................................ x = +48
#   z=-36   [ Bosque: Golem ]          [ Covil: Guardião ]
#           ----- árvores -----   |   (paredes de pedra, entrada ao sul)
#           [ Campos: Carniçais ] estrada [ Cemitério: esqueletos ]
#   z=+14   ----- árvores ------  vila  ------ árvores ------
#   z=+36   [ Vila: fonte, Anciã (missões), Ferreiro (loja), casas ]
#
# A vila é segura: a fonte cura, os monstros não vão até lá (voltam ao
# acampamento quando se afastam demais).
extends RefCounted

const NPC = preload("res://scripts/world/npc.gd")

const HALF := Vector2(48.0, 36.0)
const FOUNTAIN := Vector3(0, 0, 24)
const FOUNTAIN_RADIUS := 4.5
const ELDER := Vector3(-6.5, 0, 24)       # Anciã: missões
const MERCHANT := Vector3(6.5, 0, 25)      # Ferreiro: loja
const TALK_RANGE := 4.0
const TOWN_RADIUS := 15.0

const GROUND_COLOR := Color(0.34, 0.44, 0.3)
const PATH_COLOR := Color(0.52, 0.46, 0.35)
const PLAZA_COLOR := Color(0.56, 0.54, 0.5)
const WALL_COLOR := Color(0.4, 0.38, 0.45)
const ROCK_COLOR := Color(0.5, 0.47, 0.42)
const MEDIEVAL := "res://assets/models/kaykit/medieval/"
const BUILDING_SCALE := 5.0

# Acampamentos: "kinds" = um monstro de cada tipo da lista. Renascem `respawn` s
# depois de todos caírem.
const CAMPS := [
	{"id": "campos_1", "kinds": ["ghoul", "ghoul", "ghoul"], "pos": Vector3(-30, 0, 6), "respawn": 25.0},
	{"id": "campos_2", "kinds": ["ghoul", "ghoul"], "pos": Vector3(-20, 0, -4), "respawn": 25.0},
	{"id": "campos_3", "kinds": ["ghoul", "ghoul"], "pos": Vector3(-38, 0, -4), "respawn": 25.0},
	{"id": "cemiterio_1", "kinds": ["skeleton", "skeleton", "skeleton"], "pos": Vector3(26, 0, 6), "respawn": 30.0},
	{"id": "cemiterio_2", "kinds": ["skeleton", "skeleton", "skeleton_archer"], "pos": Vector3(36, 0, -4), "respawn": 30.0},
	{"id": "cemiterio_3", "kinds": ["skeleton_archer", "skeleton_archer"], "pos": Vector3(20, 0, -6), "respawn": 30.0},
	{"id": "bosque", "kinds": ["forest_golem"], "pos": Vector3(-27, 0, -26), "respawn": 60.0},
	{"id": "covil", "kinds": ["world_boss"], "pos": Vector3(11, 0, -27), "respawn": 120.0},
]

# Fileiras de árvores, rochedos e paredes: [centro, tamanho, estilo].
const WALLS := [
	# Vila x campos e cemitério (aberturas em |x| < 16).
	[Vector3(-31, 0, 14), Vector3(30, 2, 1.5), "trees"],
	[Vector3(31, 0, 14), Vector3(30, 2, 1.5), "trees"],
	# Campos x bosque (abertura em x = -18..-12) e o lado leste do bosque.
	[Vector3(-30, 0, -14), Vector3(24, 2, 1.5), "trees"],
	[Vector3(-12, 0, -25), Vector3(1.5, 2, 18), "trees"],
	# Covil: paredes de pedra, entrada pelo sul.
	[Vector3(2, 0, -25), Vector3(1.5, 3, 16), "mountain"],
	[Vector3(20, 0, -25), Vector3(1.5, 3, 16), "mountain"],
	# Túmulos do cemitério e pedras soltas.
	[Vector3(23, 0, 1), Vector3(1.2, 1, 1.2), "rocks"],
	[Vector3(29, 0, 0), Vector3(1.2, 1, 1.2), "rocks"],
	[Vector3(31, 0, 9), Vector3(1.2, 1, 1.2), "rocks"],
	[Vector3(40, 0, 4), Vector3(1.2, 1, 1.2), "rocks"],
	[Vector3(-6, 0, -8), Vector3(2.5, 2, 2.5), "rocks"],
	[Vector3(-44, 0, 8), Vector3(2.5, 2, 2.5), "rocks"],
	[Vector3(42, 0, -20), Vector3(3, 2, 3), "rocks"],
]

# Construções da vila (KayKit, CC0): [arquivo, posição, giro em graus, tamanho do modelo (x, z)].
const BUILDINGS := [
	["building_church_green", Vector3(0, 0, 32.5), 180.0, Vector2(1.03, 1.16)],
	["building_tavern_green", Vector3(-11, 0, 30), 180.0, Vector2(1.17, 1.33)],
	["building_blacksmith_green", Vector3(11, 0, 29.5), 180.0, Vector2(1.29, 1.25)],
	["building_market_green", Vector3(-11, 0, 19.5), 90.0, Vector2(1.8, 1.32)],
	["building_home_A_green", Vector3(-19, 0, 24), 90.0, Vector2(0.79, 0.85)],
	["building_home_B_green", Vector3(18, 0, 22), 270.0, Vector2(0.87, 1.1)],
	["building_home_A_green", Vector3(-20, 0, 32), 135.0, Vector2(0.79, 0.85)],
	["building_windmill_green", Vector3(25, 0, 31), 200.0, Vector2(1.13, 0.79)],
]
const PROPS := [
	["barrel", Vector3(14.5, 0, 25), 0.0], ["barrel", Vector3(15.3, 0, 25.6), 30.0],
	["crate_A_big", Vector3(14.6, 0, 26.6), 10.0], ["crate_open", Vector3(-6.5, 0, 17), 0.0],
	["barrel", Vector3(-7, 0, 27), 0.0],
]


static func spawn_point(index: int) -> Vector3:
	return FOUNTAIN + Vector3((index % 4 - 1.5) * 2.0, 0, -5.5)


# Nome da região onde fica `point` (mostrado no HUD).
static func zone_at(point: Vector3) -> String:
	if point.distance_to(FOUNTAIN) <= TOWN_RADIUS or point.z > 16.0:
		return "Vila"
	if point.z < -16.0 and point.x < -10.0:
		return "Bosque"
	if point.z < -16.0 and point.x > 0.0 and point.x < 22.0:
		return "Covil"
	if point.x < -10.0:
		return "Campos"
	if point.x > 12.0:
		return "Cemitério"
	return "Estrada"


static func in_town(point: Vector3) -> bool:
	return zone_at(point) == "Vila"


# Monta o mapa no `main` (chão, bordas, árvores, vila e personagens da vila).
static func build(main: Node, region: NavigationRegion3D) -> void:
	main._add_block(region, Vector3(0, -1, 0), Vector3(HALF.x * 2, 1, HALF.y * 2), GROUND_COLOR)
	main._add_block(region, Vector3(0, 0, -HALF.y), Vector3(HALF.x * 2, 2, 1), WALL_COLOR, "mountain")
	main._add_block(region, Vector3(0, 0, HALF.y), Vector3(HALF.x * 2, 2, 1), WALL_COLOR, "mountain")
	main._add_block(region, Vector3(-HALF.x, 0, 0), Vector3(1, 2, HALF.y * 2), WALL_COLOR, "mountain")
	main._add_block(region, Vector3(HALF.x, 0, 0), Vector3(1, 2, HALF.y * 2), WALL_COLOR, "mountain")
	for wall in WALLS:
		main._add_block(region, wall[0], wall[1], ROCK_COLOR if wall[2] == "rocks" else WALL_COLOR, wall[2])
	# Chão: estradas, praça, cemitério e covil (só visual).
	main._add_decal(Vector3(0, 0, -2), Vector2(6, 32), PATH_COLOR)
	main._add_decal(Vector3(-20, 0, 10), Vector2(30, 5), PATH_COLOR)
	main._add_decal(Vector3(20, 0, 10), Vector2(30, 5), PATH_COLOR)
	main._add_decal(Vector3(-15, 0, -14), Vector2(6, 8), PATH_COLOR)
	main._add_decal(FOUNTAIN, Vector2(24, 14), PLAZA_COLOR)
	main._add_decal(Vector3(28, 0, 2), Vector2(24, 20), Color(0.3, 0.34, 0.28))
	main._add_decal(Vector3(11, 0, -26), Vector2(17, 16), Color(0.32, 0.27, 0.33))
	main._add_disc(FOUNTAIN, FOUNTAIN_RADIUS, Color(0.3, 0.6, 1.0, 0.2))
	for building in BUILDINGS:
		_add_building(main, region, building[0], building[1], building[2], building[3] * BUILDING_SCALE * 0.9)
	_add_model(main, "building_well_green", FOUNTAIN, 0.0, 3.0)
	for prop in PROPS:
		_add_model(main, prop[0], prop[1], prop[2], BUILDING_SCALE)
	for data in [{"role": "elder", "pos": ELDER, "yaw": 20.0}, {"role": "merchant", "pos": MERCHANT, "yaw": -40.0}]:
		var npc := NPC.new()
		npc.role = data.role
		npc.main = main
		npc.position = data.pos
		npc.rotation.y = deg_to_rad(data.yaw)
		main.add_child(npc)


# Construção com colisão (bloqueia o caminho e entra no navmesh e no minimapa).
static func _add_building(main: Node, region: Node, file: String, at: Vector3, yaw: float, footprint: Vector2) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var size := Vector3(footprint.x, 4.0, footprint.y)
	if int(yaw) % 180 == 90:
		size = Vector3(footprint.y, 4.0, footprint.x)
	shape.size = size
	collision.shape = shape
	collision.position.y = 2.0
	body.add_child(collision)
	region.add_child(body)
	main.map_walls.append(Rect2(at.x - size.x / 2.0, at.z - size.z / 2.0, size.x, size.z))
	_add_model(main, file, at, yaw, BUILDING_SCALE)


static func _add_model(main: Node, file: String, at: Vector3, yaw: float, scale: float) -> void:
	var path := MEDIEVAL + file + ".gltf"
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = load(path).instantiate()
	model.position = at
	model.rotation.y = deg_to_rad(yaw)
	model.scale = Vector3.ONE * scale
	main.add_child(model)
