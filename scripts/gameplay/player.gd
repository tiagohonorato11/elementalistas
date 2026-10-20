# Mago. Em rede:
# - o dono (peer_id) controla movimento e mira, sincronizados para todos;
# - teclas de elemento e lançamentos viram pedidos (RPC) para o host;
# - o host roda a fila, os feitiços e o dano, e sincroniza vida/fila/efeitos para todos.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")

enum CastMode { FORWARD, AREA, SELF }

const SPEED := 5.0
const GRAVITY := 20.0
const CHANNEL_MAX := 3.0
const SPRAY_RANGE := 5.0
const SPRAY_ANGLE := 0.5236  # 30 graus
const BEAM_RANGE := 20.0
const ARC_RANGE := 8.0
const ARC_CHAIN_RANGE := 4.0
const ARC_MAX_TARGETS := 3
const AREA_RADIUS := 4.0
const PLAYER_COLORS := [Color(0.3, 0.35, 0.9), Color(0.25, 0.75, 0.35), Color(0.9, 0.55, 0.15), Color(0.65, 0.3, 0.85)]

# Teclas físicas (funcionam em qualquer layout de teclado).
const ELEMENT_KEYS := {
	KEY_Q: E.Type.WATER,
	KEY_W: E.Type.LIFE,
	KEY_E: E.Type.SHIELD,
	KEY_R: E.Type.COLD,
	KEY_A: E.Type.LIGHTNING,
	KEY_S: E.Type.ARCANE,
	KEY_D: E.Type.EARTH,
	KEY_F: E.Type.FIRE,
}

var peer_id := 1
var camera: Camera3D
var health: Health
var aim_point := Vector3.ZERO

# Estado decidido pelo host e sincronizado para todos (HUD e visual).
var queue_view: Array = []
var fx_shape: int = SpellResolver.Shape.NONE
var fx_element := 0
var fx_length := 0.0
var fx_width := 0.3

# Só usados no host.
var queue := ElementQueue.new()
var channel_elements: Array = []
var channel_shape: int = SpellResolver.Shape.NONE
var channel_time := 0.0
var _cast_dir := Vector3.ZERO   # direção enviada pelo dono no pedido de lançar

var body: MeshInstance3D
var effect_mesh: MeshInstance3D
var _shown_fx_element := -1
var _shown_dead := false


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("players")

	var collision := CollisionShape3D.new()
	collision.shape = CapsuleShape3D.new()
	collision.position.y = 1.0
	add_child(collision)

	body = MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = 1.0
	var index := maxi(Network.players.find(peer_id), 0)
	body.material_override = E.make_material(PLAYER_COLORS[index % PLAYER_COLORS.size()])
	add_child(body)

	# "Nariz" para mostrar para onde o mago está virado (-Z).
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.2, 0.2, 0.5)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 1.5, -0.5)
	add_child(nose)

	health = Health.new()
	health.name = "Health"
	health.max_hp = 200.0
	health.revivable = true
	add_child(health)
	if multiplayer.is_server():
		health.died.connect(_on_died)

	effect_mesh = MeshInstance3D.new()
	effect_mesh.mesh = BoxMesh.new()
	effect_mesh.visible = false
	add_child(effect_mesh)

	SyncUtil.add_sync(self, "MoveSync", peer_id, [".:position", ".:rotation"])
	SyncUtil.add_sync(self, "StateSync", 1, [
		".:queue_view", ".:fx_shape", ".:fx_element", ".:fx_length", ".:fx_width",
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:shielded", "Health:dead",
	])
	set_multiplayer_authority(peer_id, false)


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


# --- Entrada (só no PC do dono) ---------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or health.dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if ELEMENT_KEYS.has(key):
			request_element.rpc_id(1, ELEMENT_KEYS[key])
		elif key == KEY_SPACE:
			request_cast.rpc_id(1, CastMode.SELF, true, _forward())
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var mode := CastMode.AREA if event.shift_pressed else CastMode.FORWARD
			request_cast.rpc_id(1, mode, event.pressed, _forward())
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			request_cast.rpc_id(1, CastMode.SELF, true, _forward())


func _physics_process(delta: float) -> void:
	if is_local():
		_move_local(delta)
	if multiplayer.is_server() and _is_channeling():
		_update_channel(delta)


func _process(_delta: float) -> void:
	_update_effect_visual()
	_update_downed_visual()


# Caído: o corpo deita e fica cinza até alguém reviver com Vida.
func _update_downed_visual() -> void:
	if health.dead == _shown_dead:
		return
	_shown_dead = health.dead
	if health.dead:
		body.rotation.x = PI / 2.0
		body.position.y = 0.5
		body.transparency = 0.5
	else:
		body.rotation.x = 0.0
		body.position.y = 1.0
		body.transparency = 0.0


func _move_local(delta: float) -> void:
	_update_aim()
	if health.dead:
		velocity = Vector3.ZERO
		return

	# Andar: segurar o botão esquerdo (vai em direção ao mouse) ou setas do teclado.
	var direction := Vector3.ZERO
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		direction = aim_point - global_position
		direction.y = 0.0
		if direction.length() < 0.3:
			direction = Vector3.ZERO
	var arrows := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if arrows != Vector2.ZERO:
		direction = Vector3(arrows.x, 0.0, arrows.y)

	var speed := SPEED
	if health.chilled > 0.0:
		speed *= 0.5
	if fx_shape != SpellResolver.Shape.NONE:
		speed *= 0.4
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	var flat_aim := Vector3(aim_point.x, global_position.y, aim_point.z)
	if flat_aim.distance_to(global_position) > 0.1:
		look_at(flat_aim, Vector3.UP)


func _update_aim() -> void:
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)
	if hit != null:
		aim_point = hit


# --- Pedidos ao host ---------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_element(element: int) -> void:
	if not _from_owner() or _is_channeling():
		return
	queue.add(element)
	_publish_queue()


@rpc("any_peer", "call_local", "reliable")
func request_cast(mode: int, pressed: bool, aim: Vector3) -> void:
	if not _from_owner():
		return
	# Usa a mira que o dono viu no momento do clique (a rotação sincronizada pode atrasar).
	aim.y = 0.0
	if aim.length() > 0.1:
		_cast_dir = aim.normalized()
	_handle_cast(mode, pressed)
	_cast_dir = Vector3.ZERO


func _handle_cast(mode: int, pressed: bool) -> void:
	if not pressed:
		_stop_channel()
	elif mode == CastMode.FORWARD:
		_cast_forward()
	elif mode == CastMode.AREA:
		_cast_area()
	elif mode == CastMode.SELF:
		_cast_self()


# O host só aceita pedidos vindos do dono deste mago.
func _from_owner() -> bool:
	if not multiplayer.is_server() or health.dead:
		return false
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender == peer_id


func _publish_queue() -> void:
	queue_view = queue.elements.duplicate()


# --- Modos de lançar (host) --------------------------------------------------

func _forward() -> Vector3:
	if _cast_dir != Vector3.ZERO:
		return _cast_dir
	return -global_transform.basis.z


func _is_channeling() -> bool:
	return channel_shape != SpellResolver.Shape.NONE


func _cast_forward() -> void:
	if queue.is_empty() or _is_channeling():
		return
	var elements := queue.elements.duplicate()
	var shape := SpellResolver.resolve_shape(elements)
	if shape == SpellResolver.Shape.PROJECTILE:
		get_parent().spawn_entity({
			"type": "projectile",
			"pos": global_position + Vector3.UP,
			"dir": _forward(),
			"elements": elements,
			"caster": String(name),
		})
		_clear_queue()
	elif shape == SpellResolver.Shape.BARRIER:
		_spawn_barrier(global_position + _forward() * 2.5)
		_clear_queue()
	else:
		# Spray, beam e arco são contínuos enquanto o botão estiver pressionado.
		channel_elements = elements
		channel_shape = shape
		channel_time = 0.0
		fx_shape = shape
		fx_element = elements[0]


func _cast_area() -> void:
	if queue.is_empty() or _is_channeling():
		return
	var elements := queue.elements.duplicate()
	_clear_queue()
	if E.Type.SHIELD in elements:
		for i in 8:
			var angle := TAU * i / 8.0
			_spawn_barrier(global_position + Vector3(cos(angle), 0.0, sin(angle)) * 3.0)
		return
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= AREA_RADIUS:
			_hit(target, elements, 1.0)
	show_area_flash.rpc(elements[0])


func _cast_self() -> void:
	if queue.is_empty() or _is_channeling():
		return
	var elements := queue.elements.duplicate()
	_clear_queue()
	if E.Type.SHIELD in elements:
		health.shielded = Health.SELF_SHIELD_TIME
	health.apply_elements(elements, 1.0)


func _clear_queue() -> void:
	queue.clear()
	_publish_queue()


# --- Feitiços contínuos (host) ----------------------------------------------

func _update_channel(delta: float) -> void:
	channel_time += delta
	if channel_time >= CHANNEL_MAX:
		_stop_channel()
		return

	var length := 0.0
	var width := 0.3
	if channel_shape == SpellResolver.Shape.SPRAY:
		length = SPRAY_RANGE
		width = 2.0
		for target in _damageables():
			var offset: Vector3 = target.global_position - global_position
			offset.y = 0.0
			if offset.length() > 0.01 and offset.length() <= SPRAY_RANGE \
					and _forward().angle_to(offset.normalized()) < SPRAY_ANGLE:
				_hit(target, channel_elements, delta)
	elif channel_shape == SpellResolver.Shape.BEAM:
		var origin := global_position + Vector3.UP
		var result := _raycast(origin, origin + _forward() * BEAM_RANGE)
		length = BEAM_RANGE
		if not result.is_empty():
			length = origin.distance_to(result.position)
			_hit(result.collider, channel_elements, delta)
	elif channel_shape == SpellResolver.Shape.ARC:
		width = 0.1
		var targets := _arc_targets()
		for target in targets:
			_hit(target, channel_elements, delta)
		length = ARC_RANGE * 0.5
		if not targets.is_empty():
			length = global_position.distance_to(targets[0].global_position)
	fx_length = length
	fx_width = width


func _stop_channel() -> void:
	if not _is_channeling():
		return
	channel_shape = SpellResolver.Shape.NONE
	channel_elements = []
	fx_shape = SpellResolver.Shape.NONE
	_clear_queue()


# Alvo mais próximo à frente, depois salta para até 2 alvos vizinhos.
func _arc_targets() -> Array:
	var targets: Array = []
	var candidates := _damageables()
	var current: Node3D = null
	var best := ARC_RANGE
	for target in candidates:
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() > 0.01 and offset.length() < best \
				and _forward().angle_to(offset.normalized()) < deg_to_rad(60.0):
			best = offset.length()
			current = target
	while current != null and targets.size() < ARC_MAX_TARGETS:
		targets.append(current)
		var next: Node3D = null
		var next_best := ARC_CHAIN_RANGE
		for target in candidates:
			if target in targets:
				continue
			var distance: float = target.global_position.distance_to(current.global_position)
			if distance < next_best:
				next_best = distance
				next = target
		current = next
	return targets


# --- Visual (todos os peers) -------------------------------------------------

func _update_effect_visual() -> void:
	var active := fx_shape != SpellResolver.Shape.NONE
	effect_mesh.visible = active
	if not active:
		return
	if fx_element != _shown_fx_element:
		var color: Color = E.COLORS[fx_element]
		color.a = 0.5
		effect_mesh.material_override = E.make_material(color)
		_shown_fx_element = fx_element
	var box := effect_mesh.mesh as BoxMesh
	box.size = Vector3(fx_width, 0.3, maxf(fx_length, 0.01))
	effect_mesh.position = Vector3(0.0, 1.0, -fx_length / 2.0)


@rpc("any_peer", "call_local", "reliable")
func show_area_flash(element: int) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	var flash := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = AREA_RADIUS
	disc.bottom_radius = AREA_RADIUS
	disc.height = 0.05
	flash.mesh = disc
	var color: Color = E.COLORS[element]
	color.a = 0.4
	flash.material_override = E.make_material(color)
	add_child(flash)
	flash.position.y = 0.05
	get_tree().create_timer(0.25).timeout.connect(flash.queue_free)


# --- Utilidades (host) -------------------------------------------------------

# Inclui os outros magos: fogo amigo é intencional.
func _damageables() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("damageable"):
		if node != self and node is Node3D:
			result.append(node)
	return result


func _hit(target: Node, elements: Array, scale: float) -> void:
	var target_health := target.get_node_or_null("Health")
	if target_health != null:
		target_health.apply_elements(elements, scale)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_barrier(at: Vector3) -> void:
	var offset := at - global_position
	get_parent().spawn_entity({
		"type": "barrier",
		"pos": Vector3(at.x, 0.0, at.z),
		"yaw": atan2(offset.x, offset.z),
	})


func _on_died() -> void:
	_stop_channel()
	_clear_queue()
