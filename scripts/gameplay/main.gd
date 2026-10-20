# Arena de treino em gray-box. Em rede, o host cria magos, bonecos e efeitos
# pelo MultiplayerSpawner, que os replica para todos os jogadores.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Player = preload("res://scripts/gameplay/player.gd")
const Dummy = preload("res://scripts/gameplay/dummy.gd")
const Hud = preload("res://scripts/gameplay/hud.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")
const Barrier = preload("res://scripts/gameplay/barrier.gd")

const CAMERA_OFFSET := Vector3(0.0, 13.0, 9.0)
const DUMMY_POSITIONS := [Vector3(0, 0, -8), Vector3(5, 0, -6), Vector3(-5, 0, -6), Vector3(2, 0, -11)]
const SPAWN_POINTS := [Vector3(0, 0, 0), Vector3(2, 0, 1), Vector3(-2, 0, 1), Vector3(0, 0, 2)]

var camera: Camera3D
var hud: Hud
var spawner: MultiplayerSpawner
var local_player: Player
var _effect_counter := 0


func _ready() -> void:
	_build_environment()

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
		camera.global_position = local_player.global_position + CAMERA_OFFSET
		camera.look_at(local_player.global_position + Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Network.back_to_lobby("Você saiu da partida.")


# --- Criação de entidades (host) ---------------------------------------------

func _on_all_loaded() -> void:
	for i in DUMMY_POSITIONS.size():
		spawner.spawn({"type": "dummy", "name": "Dummy%d" % i, "pos": DUMMY_POSITIONS[i]})
	for i in Network.players.size():
		spawner.spawn({"type": "player", "id": Network.players[i], "pos": SPAWN_POINTS[i]})


func _on_player_left(peer_id: int) -> void:
	var player := get_node_or_null("Player%d" % peer_id)
	if player != null:
		player.queue_free()


# Chamado pelos magos (no host) para criar projéteis e barreiras.
func spawn_effect(data: Dictionary) -> void:
	_effect_counter += 1
	data["name"] = "%s%d" % [data.type, _effect_counter]
	spawner.spawn(data)


# Roda em todos os peers: monta a entidade a partir dos dados enviados pelo host.
func _spawn_entity(data: Dictionary) -> Node:
	var node: Node3D
	if data.type == "player":
		var player := Player.new()
		player.peer_id = data.id
		player.name = "Player%d" % data.id
		if data.id == multiplayer.get_unique_id():
			local_player = player
			player.camera = camera
			hud.player = player
		node = player
	elif data.type == "dummy":
		node = Dummy.new()
		node.name = data.name
	elif data.type == "projectile":
		var projectile := Projectile.new()
		projectile.setup(data.elements, data.caster, data.dir)
		projectile.name = data.name
		node = projectile
	elif data.type == "barrier":
		node = Barrier.new()
		node.name = data.name
		node.rotation.y = data.yaw
	node.position = data.pos
	return node


func _build_environment() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(40, 1, 40)
	collision.shape = ground_shape
	collision.position.y = -0.5
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 1, 40)
	mesh.mesh = box
	mesh.position.y = -0.5
	mesh.material_override = E.make_material(Color(0.35, 0.42, 0.3))
	ground.add_child(mesh)
	add_child(ground)

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
