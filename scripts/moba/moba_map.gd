# Mapa do modo MOBA (desenho original): duas rotas (norte e sul) com uma selva
# entre elas e a base de cada time numa ponta. O lado Vermelho é o espelho do Azul.
#
#   x = -66 ......................................... x = +66
#   [base Azul] ==== rota norte (z = -24) ==== [base Vermelha]
#               |  selva  (acampamentos, fosso do  |
#               |          Guardião no centro)     |
#   [base Azul] ==== rota sul   (z = +24) ==== [base Vermelha]
extends RefCounted

const Combat = preload("res://scripts/core/combat.gd")

const HALF := Vector2(66.0, 36.0)
const LANE_Z := 24.0
const FOUNTAIN_X := 62.0
const FOUNTAIN_RADIUS := 4.5
const TEAM_KEYS := {Combat.BLUE: "azul", Combat.RED: "vermelho"}
const LANES := ["norte", "sul"]

const GROUND_COLOR := Color(0.33, 0.42, 0.3)
const LANE_COLOR := Color(0.5, 0.45, 0.35)
const WALL_COLOR := Color(0.4, 0.38, 0.45)
const ROCK_COLOR := Color(0.5, 0.47, 0.42)

# Paredes do lado Azul (x < 0); o lado Vermelho é espelhado. [centro, tamanho]
const WALLS_HALF := [
	# Separação rota/selva (z = ±17), com passagens em x = -23 e no centro.
	[Vector3(-32, 0, -17), Vector3(12, 2, 1.5)], [Vector3(-11.5, 0, -17), Vector3(17, 2, 1.5)],
	[Vector3(-32, 0, 17), Vector3(12, 2, 1.5)], [Vector3(-11.5, 0, 17), Vector3(17, 2, 1.5)],
	# Borda externa das rotas (z = ±31).
	[Vector3(-19, 0, -31), Vector3(38, 2, 1.5)], [Vector3(-19, 0, 31), Vector3(38, 2, 1.5)],
	# Muro entre a base e a selva.
	[Vector3(-40, 0, 0), Vector3(1.5, 2, 28)],
	# Pedras da selva e o fosso do Guardião (abre para o norte e o sul).
	[Vector3(-30, 0, -6), Vector3(3, 2, 3)], [Vector3(-12, 0, 6), Vector3(2, 2, 2)],
	[Vector3(-8, 0, 0), Vector3(1.5, 2, 10)],
]

# Acampamentos da selva: o Vermelho é espelhado em x e z.
const CAMPS_HALF := [
	{"id": "lobos", "kind": "jungle_wolf", "count": 2, "pos": Vector3(-28, 0, 8), "respawn": 60.0},
	{"id": "golem", "kind": "jungle_golem", "count": 1, "pos": Vector3(-16, 0, -8), "respawn": 90.0},
]
const BOSS_CAMP := {"id": "guardiao", "kind": "boss", "count": 1, "pos": Vector3(0, 0, 0), "respawn": 180.0}


# -1 para o Azul (esquerda), +1 para o Vermelho (direita).
static func side(team: int) -> float:
	return -1.0 if team == Combat.BLUE else 1.0


static func fountain(team: int) -> Vector3:
	return Vector3(FOUNTAIN_X * side(team), 0, 0)


static func spawn_point(team: int, index: int) -> Vector3:
	return fountain(team) + Vector3(0, 0, (index % 3 - 1) * 2.5)


static func lane_sign(lane: String) -> float:
	return -1.0 if lane == "norte" else 1.0


# Caminho das tropas de `team` na rota `lane`, da própria base até o nexus inimigo.
static func lane_path(team: int, lane: String) -> Array:
	var z := lane_sign(lane)
	var points := [
		Vector3(-50, 0, 4 * z), Vector3(-43, 0, 16 * z), Vector3(-34, 0, LANE_Z * z),
		Vector3(34, 0, LANE_Z * z), Vector3(43, 0, 16 * z), Vector3(50, 0, 4 * z), Vector3(54, 0, 0),
	]
	if team == Combat.RED:
		points = points.map(func(point): return Vector3(-point.x, 0, point.z))
	return points


# Torres, inibidores e nexus. Uma estrutura com "requires" fica invulnerável
# até QUALQUER uma das estruturas listadas cair.
static func structures() -> Array:
	var list := []
	for team in [Combat.BLUE, Combat.RED]:
		var s := side(team)
		var key: String = TEAM_KEYS[team]
		for lane in LANES:
			var z := lane_sign(lane)
			var outer := "%s_%s_torre_externa" % [key, lane]
			var inner := "%s_%s_torre_interna" % [key, lane]
			list.append({"id": outer, "kind": "tower", "team": team, "lane": lane,
				"pos": Vector3(16 * s, 0, LANE_Z * z), "requires": []})
			list.append({"id": inner, "kind": "tower", "team": team, "lane": lane,
				"pos": Vector3(31 * s, 0, LANE_Z * z), "requires": [outer]})
			list.append({"id": "%s_%s_inibidor" % [key, lane], "kind": "inhibitor", "team": team, "lane": lane,
				"pos": Vector3(45 * s, 0, 17 * z), "requires": [inner]})
		var nexus_tower := "%s_torre_nexus" % key
		list.append({"id": nexus_tower, "kind": "tower", "team": team, "lane": "",
			"pos": Vector3(49 * s, 0, 0), "requires": ["%s_norte_inibidor" % key, "%s_sul_inibidor" % key]})
		list.append({"id": "%s_nexus" % key, "kind": "nexus", "team": team, "lane": "",
			"pos": Vector3(54 * s, 0, 0), "requires": [nexus_tower]})
	return list


static func camps() -> Array:
	var list := []
	for camp in CAMPS_HALF:
		for team in [Combat.BLUE, Combat.RED]:
			var entry: Dictionary = camp.duplicate()
			entry.id = "%s_%s" % [camp.id, TEAM_KEYS[team]]
			entry.pos = camp.pos if team == Combat.BLUE else -camp.pos
			list.append(entry)
	list.append(BOSS_CAMP.duplicate())
	return list


# Monta a geometria no `main` (chão, paredes, rotas, fontes) e gera o navmesh.
static func build(main: Node, region: NavigationRegion3D) -> void:
	main._add_block(region, Vector3(0, -1, 0), Vector3(HALF.x * 2, 1, HALF.y * 2), GROUND_COLOR)
	main._add_block(region, Vector3(0, 0, -HALF.y), Vector3(HALF.x * 2, 2, 1), WALL_COLOR)
	main._add_block(region, Vector3(0, 0, HALF.y), Vector3(HALF.x * 2, 2, 1), WALL_COLOR)
	main._add_block(region, Vector3(-HALF.x, 0, 0), Vector3(1, 2, HALF.y * 2), WALL_COLOR)
	main._add_block(region, Vector3(HALF.x, 0, 0), Vector3(1, 2, HALF.y * 2), WALL_COLOR)
	for wall in WALLS_HALF:
		var color := ROCK_COLOR if wall[1].x <= 3.0 else WALL_COLOR
		main._add_block(region, wall[0], wall[1], color)
		main._add_block(region, Vector3(-wall[0].x, 0, -wall[0].z), wall[1], color)
	# Faixas das rotas e fontes (só visual).
	for lane in LANES:
		main._add_decal(Vector3(0, 0, LANE_Z * lane_sign(lane)), Vector2(76, 7), LANE_COLOR)
	for team in [Combat.BLUE, Combat.RED]:
		var color: Color = Combat.TEAM_COLORS[team]
		color.a = 0.35
		main._add_disc(fountain(team), FOUNTAIN_RADIUS, color)
