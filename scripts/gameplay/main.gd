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
const Zone = preload("res://scripts/gameplay/zone.gd")
const Dummy = preload("res://scripts/practice/dummy.gd")
const PracticeState = preload("res://scripts/practice/practice_state.gd")
const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const MobaState = preload("res://scripts/moba/moba_state.gd")
const Structure = preload("res://scripts/moba/structure.gd")
const Minion = preload("res://scripts/moba/minion.gd")
const TerrainShader = preload("res://assets/shaders/terrain.gdshader")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const GameAudio = preload("res://scripts/audio/game_audio.gd")

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
var game_state: Node          # GameState (Arena), MobaState ou PracticeState (Treino)
var mode := "arena"
var zoom := 1.0               # rodinha do mouse: aproxima/afasta a câmera
# Para o minimapa: metade do mapa (x, z), paredes e rotas como retângulos no chão.
var map_half := Vector2(ARENA_SIZE / 2.0, ARENA_SIZE / 2.0)
var map_walls: Array[Rect2] = []
var map_lanes: Array[Rect2] = []
var _entity_counter := 0
var _terrain_materials := {}
var _shake := 0.0             # tremor da câmera (impactos grandes perto do jogador)
const SHAKE_RANGE := 25.0
const SHAKE_DECAY := 2.5
const SHAKE_AMOUNT := 0.45


func _ready() -> void:
	mode = Network.game_mode()
	# Arena é cooperativa (fogo amigo ligado); no MOBA e no Treino aliados não se ferem.
	Combat.friendly_fire = mode == "arena"
	_build_world()

	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.UP)

	hud = Hud.new()
	add_child(hud)
	add_child(GameAudio.new())

	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _spawn_entity
	add_child(spawner)

	if multiplayer.is_server():
		Network.all_loaded.connect(_on_all_loaded, CONNECT_ONE_SHOT)
		Network.player_left.connect(_on_player_left)
	Network.report_loaded()


func _process(delta: float) -> void:
	if is_instance_valid(local_player):
		var offset := MOBA_CAMERA_OFFSET if mode == "moba" else CAMERA_OFFSET
		camera.global_position = local_player.global_position + offset * zoom
		camera.look_at(local_player.global_position + Vector3.UP)
		if _shake > 0.0:
			camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) \
				* _shake * SHAKE_AMOUNT
			_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)


# Impacto visto neste PC: treme a câmera (mais forte perto do jogador) e, nos
# muito grandes (força >= 1, como as versões MEGA), dá um clarão na tela.
func impact(at: Vector3, strength: float, color := Color.WHITE) -> void:
	if not is_instance_valid(local_player):
		return
	var distance := local_player.global_position.distance_to(at)
	if distance > SHAKE_RANGE:
		return
	var felt := strength * (1.0 - distance / SHAKE_RANGE)
	_shake = maxf(_shake, felt)
	if strength >= 1.0:
		hud.flash(color, 0.35 * felt)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.08, 0.5, 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.08, 0.5, 1.5)
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
	if mode == "practice":
		spawn_entity({"type": "practice_state", "pos": Vector3.ZERO})
	else:
		spawn_entity({"type": "state", "pos": Vector3.ZERO})
	for i in Network.players.size():
		var peer: int = Network.players[i]
		spawn_entity({"type": "player", "id": peer, "class": Network.class_of(peer), "team": Combat.BLUE,
			"elements": Network.elements_of(peer), "color": i, "pos": SPAWN_POINTS[i % SPAWN_POINTS.size()]})
	if mode == "practice":
		game_state.start()


# MOBA: estado da partida, estruturas e selva, jogadores nos times e bots completando.
func _start_moba() -> void:
	var state: Node = spawn_entity({"type": "moba_state", "pos": Vector3.ZERO})
	state.start(self)
	var slots := {Combat.BLUE: 0, Combat.RED: 0}
	var champions := []
	for peer in Network.players:
		var team := Network.team_of(peer)
		champions.append({"type": "player", "id": peer, "class": Network.class_of(peer), "team": team,
			"elements": Network.elements_of(peer), "color": slots[team], "pos": MobaMap.spawn_point(team, slots[team])})
		slots[team] += 1
	var bot_id := BOT_ID_START
	for bot in Network.bot_plan():
		champions.append({"type": "player", "id": bot_id, "bot": true, "class": bot.class, "team": bot.team,
			"elements": bot.elements, "color": slots[bot.team], "pos": MobaMap.spawn_point(bot.team, slots[bot.team])})
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
	elif data.type == "state" or data.type == "moba_state" or data.type == "practice_state":
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
		player.elements = data.get("elements", [])
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
			data.get("team", Combat.NEUTRAL), data.get("damage", 0.0), data.get("style", "orb"),
			data.get("backstab", 1.0), data.get("splash", 0.0))
		node = projectile
	elif data.type == "barrier":
		var barrier := Barrier.new()
		barrier.setup(data.get("elements", []), data.get("team", Combat.NEUTRAL))
		barrier.rotation.y = data.yaw
		node = barrier
	elif data.type == "meteor":
		var meteor := Meteor.new()
		meteor.team = data.get("team", Combat.NEUTRAL)
		meteor.extra = data.get("extra", [])
		meteor.strength = data.get("strength", 1.0)
		meteor.caster_name = data.get("caster", "")
		meteor.zone_elements = data.get("zone_elements", [])
		meteor.mini = data.get("mini", false)
		meteor.elements = data.get("elements", [])
		meteor.damage = data.get("damage", 0.0)
		meteor.radius = data.get("radius", Meteor.RADIUS)
		meteor.zone_time = data.get("zone_time", Meteor.ZONE_TIME)
		node = meteor
	elif data.type == "zone":
		var zone := Zone.new()
		zone.team = data.get("team", Combat.NEUTRAL)
		zone.caster_name = data.get("caster", "")
		zone.elements = data.get("elements", [])
		zone.strength = data.get("strength", 1.0)
		zone.radius = data.get("radius", 3.5)
		zone.duration = data.get("duration", 3.0)
		zone.dps = data.get("dps", 0.0)
		node = zone
	elif data.type == "state":
		game_state = GameState.new()
		hud.game_state = game_state
		node = game_state
	elif data.type == "moba_state":
		game_state = MobaState.new()
		hud.game_state = game_state
		node = game_state
	elif data.type == "practice_state":
		game_state = PracticeState.new()
		hud.game_state = game_state
		node = game_state
	elif data.type == "dummy":
		var dummy := Dummy.new()
		dummy.kind = data.kind
		node = dummy
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
		map_half = MobaMap.HALF
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
		var style := "rocks" if obstacle[1].x == obstacle[1].z else "trees"
		_add_block(region, obstacle[0], obstacle[1], Color(0.5, 0.47, 0.42), style)


# Sol com sombras, céu, brilho (bloom) para os efeitos, névoa leve e oclusão de ambiente.
func _add_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_material.ground_horizon_color = Color(0.45, 0.5, 0.45)
	sky_material.ground_bottom_color = Color(0.2, 0.24, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.85)
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


# Material do terreno (shader com variação de cor) a partir de uma cor base.
# Superfícies largas e baixas viram gramado com manchas de terra; o resto, pedra.
func _terrain_material(color: Color, ground: bool) -> ShaderMaterial:
	var key := [color, ground]
	if _terrain_materials.has(key):
		return _terrain_materials[key]
	var material := ShaderMaterial.new()
	material.shader = TerrainShader
	material.set_shader_parameter("color_a", color.darkened(0.12))
	material.set_shader_parameter("color_b", color.lightened(0.1))
	if ground:
		material.set_shader_parameter("color_a", color.darkened(0.25))
		material.set_shader_parameter("color_b", color.lightened(0.12))
		material.set_shader_parameter("color_c", Color(0.42, 0.34, 0.22))
		material.set_shader_parameter("scale", 0.25)
		material.set_shader_parameter("patch_amount", 0.35)
	else:
		material.set_shader_parameter("color_c", Color(0.32, 0.4, 0.28))
		material.set_shader_parameter("scale", 0.9)
		material.set_shader_parameter("patch_amount", 0.15)
	_terrain_materials[key] = material
	return material


# Faixa colorida no chão (só visual: rotas).
func _add_decal(at: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.02, size.y)
	mesh.mesh = box
	mesh.material_override = _terrain_material(color, true)
	mesh.position = at + Vector3(0, 0.01, 0)
	add_child(mesh)
	map_lanes.append(Rect2(at.x - size.x / 2.0, at.z - size.y / 2.0, size.x, size.y))


# Disco no chão (só visual: fontes).
func _add_disc(at: Vector3, radius: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.03
	mesh.mesh = disc
	mesh.material_override = Vfx.glow_material(Color(color, 1.0), 1.0, color.a)
	mesh.position = at + Vector3(0, 0.02, 0)
	add_child(mesh)


# Bloco estático com a base em `at.y` (o chão tem o topo em y = 0).
# style: "stone" (bloco de pedra visível), "trees" (fileira de árvores),
# "rocks" (pedras) ou "mountain" (morro com árvores). A colisão é sempre o bloco.
func _add_block(parent: Node, at: Vector3, size: Vector3, color: Color, style := "stone") -> void:
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
	mesh.material_override = _terrain_material(color, size.y <= 1.0 and size.x >= 20.0)
	block.add_child(mesh)
	parent.add_child(block)
	if at.y >= 0.0:
		map_walls.append(Rect2(at.x - size.x / 2.0, at.z - size.z / 2.0, size.x, size.z))
	if style != "stone":
		mesh.visible = false
		_decorate(block, size, style)


const MEDIEVAL := "res://assets/models/kaykit/medieval/"
const DECOR := {
	"trees": [["trees_A_large.gltf", "trees_B_large.gltf", "trees_A_medium.gltf", "trees_B_medium.gltf"], 2.4, 3.0],
	"rocks": [["mountain_A_grass_trees.gltf", "mountain_B_grass_trees.gltf"], 1.1, 2.0],
	"mountain": [["mountain_A_grass_trees.gltf", "mountain_B_grass_trees.gltf", "hills_A_trees.gltf"], 2.6, 4.0],
}
var _decor_scenes := {}


# Modelos (KayKit Medieval Hexagon, CC0) ao longo do comprimento do bloco.
# Posições e giros vêm de um sorteio com semente fixa: iguais em todos os PCs.
func _decorate(block: Node3D, size: Vector3, style: String) -> void:
	var config: Array = DECOR[style]
	var files: Array = config[0]
	var scale_factor: float = config[1]
	var spacing: float = config[2]
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var count := maxi(int(length / spacing), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(block.position)
	for i in count:
		var t := (i + 0.5) / count - 0.5
		var offset := Vector3(t * length, -size.y / 2.0, 0) if along_x else Vector3(0, -size.y / 2.0, t * length)
		var file: String = files[rng.randi() % files.size()]
		if not _decor_scenes.has(file):
			_decor_scenes[file] = load(MEDIEVAL + file)
		var decor: Node3D = _decor_scenes[file].instantiate()
		decor.position = offset
		decor.rotation.y = rng.randf() * TAU
		decor.scale = Vector3.ONE * scale_factor * rng.randf_range(0.85, 1.15)
		block.add_child(decor)
