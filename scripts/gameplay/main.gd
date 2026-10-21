# Cena da partida em gray-box: Arena (ondas, cooperativo) ou MOBA (dois times).
# Em rede, o host cria personagens, inimigos, efeitos e o estado da partida pelo
# MultiplayerSpawner, que os replica para todos os jogadores.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Player = preload("res://scripts/gameplay/player.gd")
const Enemy = preload("res://scripts/gameplay/enemy.gd")
const GameState = preload("res://scripts/gameplay/game_state.gd")
const Hud = preload("res://scripts/gameplay/hud.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Barrier = preload("res://scripts/gameplay/barrier.gd")
const Meteor = preload("res://scripts/gameplay/meteor.gd")
const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const MobaState = preload("res://scripts/moba/moba_state.gd")
const Structure = preload("res://scripts/moba/structure.gd")
const Minion = preload("res://scripts/moba/minion.gd")

const CAMERA_OFFSET := Vector3(0.0, 13.0, 9.0)
const MOBA_CAMERA_OFFSET := Vector3(0.0, 16.0, 11.0)
const ARENA_SIZE := 40.0
const SPAWN_POINTS := [Vector3(0, 0, 0), Vector3(2, 0, 1), Vector3(-2, 0, 1), Vector3(0, 0, 2),
	Vector3(2, 0, -1), Vector3(-2, 0, -1)]
const BOT_ID_START := 1000
# Obstáculos: [posição, tamanho].
const OBSTACLES := [
	[Vector3(-7, 0, -7), Vector3(2, 3, 2)],
	[Vector3(7, 0, -7), Vector3(2, 3, 2)],
	[Vector3(-7, 0, 7), Vector3(2, 3, 2)],
	[Vector3(7, 0, 7), Vector3(2, 3, 2)],
	[Vector3(-12, 0, 0), Vector3(1, 1.5, 6)],
	[Vector3(12, 0, 0), Vector3(1, 1.5, 6)],
	[Vector3(0, 0, -11), Vector3(6, 1.5, 1)],
]

var camera: Camera3D
var hud: Hud
var spawner: MultiplayerSpawner
var local_player: Player
var game_state: Node          # GameState (Arena) ou MobaState
var mode := "arena"
var _entity_counter := 0


func _ready() -> void:
	mode = Network.game_mode()
	# Arena é cooperativa (fogo amigo ligado); no MOBA aliados não se ferem.
	Combat.friendly_fire = mode != "moba"
	_build_world()

	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.UP)

	hud = Hud.new()
	add_child(hud)

	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _spawn_entity
	add_child(spawner)

	if multiplayer.is_server():
		Network.all_loaded.connect(_on_all_loaded, CONNECT_ONE_SHOT)
		Network.player_left.connect(_on_player_left)
	Network.report_loaded()


func _process(_delta: float) -> void:
	if is_instance_valid(local_player):
		camera.global_position = local_player.global_position + (MOBA_CAMERA_OFFSET if mode == "moba" else CAMERA_OFFSET)
		camera.look_at(local_player.global_position + Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		Network.back_to_lobby("Você saiu da partida.")
	elif event.physical_keycode == KEY_R and multiplayer.is_server() \
			and is_instance_valid(game_state) and game_state.is_over():
		Network.restart_game()


# --- Criação de entidades (host) ---------------------------------------------

func _on_all_loaded() -> void:
	if mode == "moba":
		_start_moba()
		return
	spawn_entity({"type": "state", "pos": Vector3.ZERO})
	for i in Network.players.size():
		var peer: int = Network.players[i]
		spawn_entity({"type": "player", "id": peer, "class": Network.class_of(peer), "team": Combat.BLUE,
			"color": i, "pos": SPAWN_POINTS[i % SPAWN_POINTS.size()]})


# MOBA: estado da partida, estruturas e selva, jogadores nos times e bots completando.
func _start_moba() -> void:
	var state: Node = spawn_entity({"type": "moba_state", "pos": Vector3.ZERO})
	state.start(self)
	var slots := {Combat.BLUE: 0, Combat.RED: 0}
	var champions := []
	for peer in Network.players:
		var team := Network.team_of(peer)
		champions.append({"type": "player", "id": peer, "class": Network.class_of(peer), "team": team,
			"color": slots[team], "pos": MobaMap.spawn_point(team, slots[team])})
		slots[team] += 1
	var bot_id := BOT_ID_START
	for bot in Network.bot_plan():
		champions.append({"type": "player", "id": bot_id, "bot": true, "class": bot.class, "team": bot.team,
			"color": slots[bot.team], "pos": MobaMap.spawn_point(bot.team, slots[bot.team])})
		slots[bot.team] += 1
		bot_id += 1
	for data in champions:
		state.register_champion(spawn_entity(data))


func _on_player_left(peer_id: int) -> void:
	var player := get_node_or_null("Player%d" % peer_id)
	if player != null:
		player.queue_free()


# Chamado no host para criar qualquer entidade replicada; devolve o nó criado.
func spawn_entity(data: Dictionary) -> Node:
	_entity_counter += 1
	if data.type == "player":
		data["name"] = ("Bot%d" if data.get("bot", false) else "Player%d") % data.id
	elif data.type == "state" or data.type == "moba_state":
		data["name"] = "GameState"
	elif data.type == "structure":
		data["name"] = data.id
	else:
		data["name"] = "%s%d" % [data.type, _entity_counter]
	return spawner.spawn(data)


# Roda em todos os peers: monta a entidade a partir dos dados enviados pelo host.
func _spawn_entity(data: Dictionary) -> Node:
	var node: Node3D
	if data.type == "player":
		var player := Player.new()
		player.is_bot = data.get("bot", false)
		# Bots são controlados pelo host (dono = 1).
		player.peer_id = 1 if player.is_bot else data.id
		player.class_id = data.get("class", "mage")
		player.team = data.get("team", Combat.BLUE)
		player.color_index = data.get("color", 0)
		if not player.is_bot and data.id == multiplayer.get_unique_id():
			local_player = player
			player.camera = camera
			hud.player = player
		node = player
	elif data.type == "enemy":
		var enemy := Enemy.new()
		enemy.kind = data.kind
		enemy.team = data.get("team", Combat.RED)
		enemy.camp_position = data.get("camp", Vector3.ZERO)
		node = enemy
	elif data.type == "projectile":
		var projectile := Projectile.new()
		projectile.setup(data.elements, data.caster, data.dir, data.get("power", 1.0), data.get("speed", 18.0),
			data.get("team", Combat.NEUTRAL))
		node = projectile
	elif data.type == "barrier":
		var barrier := Barrier.new()
		barrier.setup(data.get("elements", []), data.get("team", Combat.NEUTRAL))
		barrier.rotation.y = data.yaw
		node = barrier
	elif data.type == "meteor":
		var meteor := Meteor.new()
		meteor.team = data.get("team", Combat.NEUTRAL)
		node = meteor
	elif data.type == "state":
		game_state = GameState.new()
		hud.game_state = game_state
		node = game_state
	elif data.type == "moba_state":
		game_state = MobaState.new()
		hud.game_state = game_state
		node = game_state
	elif data.type == "structure":
		var structure := Structure.new()
		structure.kind = data.kind
		structure.team = data.team
		structure.struct_id = data.id
		structure.lane = data.lane
		node = structure
	elif data.type == "minion":
		var minion := Minion.new()
		minion.kind = data.kind
		minion.team = data.team
		minion.path = MobaMap.lane_path(data.team, data.lane)
		node = minion
	node.name = data.name
	node.position = data.pos
	return node


# --- Mapa --------------------------------------------------------------------

func _build_world() -> void:
	# Chão, bordas e obstáculos ficam dentro da região de navegação.
	var region := NavigationRegion3D.new()
	add_child(region)
	if mode == "moba":
		MobaMap.build(self, region)
	else:
		_build_arena(region)

	# Navmesh em todos os PCs: o host move os inimigos e cada jogador calcula
	# o caminho do próprio personagem (andar clicando).
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.75
	nav_mesh.agent_height = 2.0
	region.navigation_mesh = nav_mesh
	region.bake_navigation_mesh(false)
	_add_lights()


func _build_arena(region: NavigationRegion3D) -> void:
	_add_block(region, Vector3(0, -1, 0), Vector3(ARENA_SIZE, 1, ARENA_SIZE), Color(0.35, 0.42, 0.3))
	var half := ARENA_SIZE / 2.0
	var wall_color := Color(0.4, 0.38, 0.45)
	_add_block(region, Vector3(0, 0, -half), Vector3(ARENA_SIZE, 2, 1), wall_color)
	_add_block(region, Vector3(0, 0, half), Vector3(ARENA_SIZE, 2, 1), wall_color)
	_add_block(region, Vector3(-half, 0, 0), Vector3(1, 2, ARENA_SIZE), wall_color)
	_add_block(region, Vector3(half, 0, 0), Vector3(1, 2, ARENA_SIZE), wall_color)
	for obstacle in OBSTACLES:
		_add_block(region, obstacle[0], obstacle[1], Color(0.5, 0.47, 0.42))


func _add_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	world.environment = env
	add_child(world)


# Faixa colorida no chão (só visual: rotas).
func _add_decal(at: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.02, size.y)
	mesh.mesh = box
	mesh.material_override = E.make_material(color)
	mesh.position = at + Vector3(0, 0.01, 0)
	add_child(mesh)


# Disco no chão (só visual: fontes).
func _add_disc(at: Vector3, radius: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.03
	mesh.mesh = disc
	mesh.material_override = E.make_material(color)
	mesh.position = at + Vector3(0, 0.02, 0)
	add_child(mesh)


# Bloco estático com a base em `at.y` (o chão tem o topo em y = 0).
func _add_block(parent: Node, at: Vector3, size: Vector3, color: Color) -> void:
	var block := StaticBody3D.new()
	block.position = at + Vector3(0, size.y / 2.0, 0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	block.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = E.make_material(color)
	block.add_child(mesh)
	parent.add_child(block)
