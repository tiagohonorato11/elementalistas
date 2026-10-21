# Personagem jogável (Mago, Assassino ou Lutador — ver scripts/core/classes.gd). Em rede:
# - o dono (peer_id) controla movimento e mira, sincronizados para todos;
# - teclas de elemento e lançamentos viram pedidos (RPC) para o host;
# - o host roda a fila, os feitiços e o dano, e sincroniza vida/fila/efeitos para todos.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Specials = preload("res://scripts/core/specials.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const BotBrain = preload("res://scripts/moba/bot_brain.gd")
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")

enum CastMode { FORWARD, AREA, SELF }

const GRAVITY := 20.0
const CHANNEL_MAX := 3.0
# Disparo automático: depois de 1 s sem novo elemento/habilidade, a fila é lançada
# à frente (na direção do mouse). Spray, beam e arco duram AUTO_CHANNEL_TIME.
const AUTO_CAST_DELAY := 1.0
const AUTO_CHANNEL_TIME := 2.0
# Andar clicando.
const ARRIVE_DISTANCE := 0.3
const STUCK_TIME := 0.4
const SPRAY_RANGE := 5.0
const SPRAY_ANGLE := 0.5236  # 30 graus
const BEAM_RANGE := 20.0
const ARC_RANGE := 8.0
const ARC_CHAIN_RANGE := 4.0
const ARC_MAX_TARGETS := 3
const AREA_RADIUS := 4.0
const PLAYER_COLORS := [Color(0.3, 0.35, 0.9), Color(0.25, 0.75, 0.35), Color(0.9, 0.55, 0.15), Color(0.65, 0.3, 0.85)]

# Projétil carregado: segurar até CHARGE_TIME leva o poder de MIN a MAX.
const CHARGE_TIME := 1.2
const PROJECTILE_POWER := Vector2(0.6, 2.0)
const PROJECTILE_SPEED := Vector2(14.0, 28.0)

# Habilidades de classe (os números da arma ficam em classes.gd).
const ARCANE_SHIELD_TIME := 4.0
const ARCANE_SHIELD_RADIUS := 4.0
const ARCANE_SHIELD_PUSH := 7.0
const INVISIBLE_TIME := 3.0
const DASH_TIME := 0.35
const DASH_SPEED := 20.0     # 20 m/s por 0,35 s = 7 m
const DASH_DAMAGE := 30.0
const DASH_PUSH := 10.0
const DASH_HIT_RADIUS := 1.6

# Empurrão.
const PUSH_DECAY := 18.0
const MAX_PUSH := 12.0
const SPRAY_WATER_PUSH := 25.0  # por segundo, por Água na fila
const AREA_WATER_PUSH := 6.0

# Feitiços especiais.
const ARENA_LIMIT := 18.5
const METEOR_RANGE := 14.0
const TELEPORT_RANGE := 10.0
const STORM_TIME := 5.0
const STORM_INTERVAL := 0.5
const STORM_RANGE := 14.0
const FROST_RADIUS := 10.0
const FROST_TIME := 3.5

# Ações configuráveis (ver scripts/ui/keybinds.gd) -> elemento.
const ELEMENT_ACTIONS := {
	"element_water": E.Type.WATER,
	"element_life": E.Type.LIFE,
	"element_shield": E.Type.SHIELD,
	"element_cold": E.Type.COLD,
	"element_lightning": E.Type.LIGHTNING,
	"element_arcane": E.Type.ARCANE,
	"element_earth": E.Type.EARTH,
	"element_fire": E.Type.FIRE,
}

var peer_id := 1               # dono do personagem (bots: o host)
var team := Combat.BLUE
var is_bot := false            # controlado pela IA no host (ver bot_brain.gd)
var color_index := 0
var power := 1.0               # multiplicador de dano (níveis, itens e bônus no MOBA)
var class_id := Classes.DEFAULT
var cls: Dictionary          # dados da classe (classes.gd)
var moba := false            # modo MOBA: ouro, níveis, loja e reaparecer na base

# MOBA (decidido pelo host e sincronizado).
var gold := Progression.START_GOLD
var xp := 0
var level := 1
var items: Array = []
var buffs := {}               # id do bônus -> segundos restantes
var respawn_time := 0.0       # > 0: caído, esperando para voltar na base
var speed_bonus := 0.0
var cooldown_mult := 1.0
var _gold_fraction := 0.0
var camera: Camera3D
var health: Health
var aim_point := Vector3.ZERO
var push_velocity := Vector3.ZERO   # empurrão, aplicado pelo dono no movimento

# Estado decidido pelo host e sincronizado para todos (HUD e visual).
var queue_view: Array = []
var fx_shape: int = SpellResolver.Shape.NONE
var fx_element := 0
var fx_length := 0.0   # comprimento do efeito; no projétil, a carga (0 a 1)
var fx_width := 0.3
var special_cooldowns := {}
var ability_cooldown := 0.0
var weapon_elements: Array = []   # elementos na arma (o Assassino guarda por 3 golpes)
var weapon_charges := 0
var invisible := 0.0              # Passo sombrio: os inimigos ignoram
var auto_cast_timer := 0.0        # contagem até o disparo automático

# Só usados no host.
var queue := ElementQueue.new()
var channel_elements: Array = []
var channel_shape: int = SpellResolver.Shape.NONE
var channel_time := 0.0
var channel_limit := CHANNEL_MAX
var weapon_timer := 0.0
var storm_time := 0.0
var storm_tick := 0.0
var dash_hit_time := 0.0      # Investida em andamento (host)
var dash_direction := Vector3.ZERO
var dash_elements: Array = []
var dash_hit: Array = []
var _cast_dir := Vector3.ZERO   # direção enviada pelo dono no pedido de lançar

# Investida: o dono move o personagem (só no PC dele).
var dash_velocity := Vector3.ZERO
var dash_time := 0.0

# Andar clicando (só no PC do dono).
var nav_agent: NavigationAgent3D
var move_target := Vector3.ZERO
var has_move_target := false
var _stuck_time := 0.0

var body: MeshInstance3D
var body_parts: Array = []    # corpo + acessórios (ficam transparentes juntos)
var effect_mesh: MeshInstance3D
var _shown_fx_element := -1
var _shown_dead := false


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("players")
	cls = Classes.info(class_id)
	moba = Network.game_mode() == "moba"
	_build_body()

	health = Health.new()
	health.name = "Health"
	health.max_hp = cls.hp
	health.armor = cls.armor
	# Arena: caído espera um aliado com Vida. MOBA: volta sozinho na base.
	health.revivable = not moba
	add_child(health)
	if multiplayer.is_server():
		health.died.connect(_on_died)
		if moba:
			_recompute_stats()

	effect_mesh = MeshInstance3D.new()
	effect_mesh.mesh = BoxMesh.new()
	effect_mesh.visible = false
	add_child(effect_mesh)

	SyncUtil.add_sync(self, "MoveSync", peer_id, [".:position", ".:rotation"])
	SyncUtil.add_sync(self, "StateSync", 1, [
		".:queue_view", ".:fx_shape", ".:fx_element", ".:fx_length", ".:fx_width", ".:special_cooldowns",
		".:ability_cooldown", ".:weapon_elements", ".:weapon_charges", ".:invisible", ".:auto_cast_timer",
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:shielded", "Health:dead",
		"Health:frozen", "Health:ward", "Health:ward_elements", "Health:max_hp",
		".:gold", ".:xp", ".:level", ".:items", ".:buffs", ".:respawn_time", ".:speed_bonus", ".:cooldown_mult",
	])
	set_multiplayer_authority(peer_id, false)

	if is_local():
		nav_agent = NavigationAgent3D.new()
		nav_agent.radius = 0.5
		nav_agent.avoidance_enabled = false
		# O navmesh fica 0,5 m acima da origem do personagem (que está no chão).
		nav_agent.path_height_offset = 0.5
		nav_agent.path_desired_distance = 0.4
		nav_agent.target_desired_distance = ARRIVE_DISTANCE
		add_child(nav_agent)

	# Bots: a IA roda no host e usa os mesmos pedidos que um jogador.
	if is_bot and multiplayer.is_server():
		var brain := BotBrain.new()
		brain.name = "BotBrain"
		add_child(brain)


# Gray-box: a cor identifica o jogador; o formato e os acessórios, a classe.
func _build_body() -> void:
	var radius := 0.5
	if class_id == "assassin":
		radius = 0.4
	elif class_id == "fighter":
		radius = 0.6

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	collision.shape = capsule
	collision.position.y = 1.0
	add_child(collision)

	body = MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = radius
	body.mesh = capsule_mesh
	body.position.y = 1.0
	var color: Color = PLAYER_COLORS[color_index % PLAYER_COLORS.size()]
	if moba:
		# MOBA: a cor do time, em tons diferentes para cada campeão.
		color = Combat.TEAM_COLORS[team].darkened(0.15 * (color_index % 3))
	body.material_override = E.make_material(color)
	add_child(body)
	body_parts = [body]

	# "Nariz" para mostrar para onde o personagem está virado (-Z).
	_add_part(BoxMesh.new(), Vector3(0.2, 0.2, 0.5), Vector3(0.0, 0.5, -radius), Color(0.9, 0.9, 0.9))
	if class_id == "mage":
		var hat := CylinderMesh.new()
		hat.top_radius = 0.0
		hat.bottom_radius = 0.45
		hat.height = 0.7
		_add_part(hat, Vector3.ONE, Vector3(0.0, 1.3, 0.0), Color(0.3, 0.2, 0.5))
	elif class_id == "assassin":
		_add_part(BoxMesh.new(), Vector3(0.7, 0.18, 0.5), Vector3(0.0, 0.55, -0.1), Color(0.12, 0.12, 0.15))
	elif class_id == "fighter":
		_add_part(BoxMesh.new(), Vector3(1.5, 0.25, 0.55), Vector3(0.0, 0.6, 0.0), Color(0.55, 0.55, 0.6))

	var label := Label3D.new()
	label.text = cls.label
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.6
	add_child(label)


func _add_part(mesh: PrimitiveMesh, size: Vector3, at: Vector3, color: Color) -> void:
	if mesh is BoxMesh:
		mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = E.make_material(color)
	body.add_child(part)
	body_parts.append(part)


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


# --- Entrada (só no PC do dono) ---------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_bot or not is_local() or health.dead:
		return
	for action in ELEMENT_ACTIONS:
		if event.is_action_pressed(action):
			request_element.rpc_id(1, ELEMENT_ACTIONS[action])
			return
	if event.is_action_pressed("move_to_cursor"):
		_show_move_marker(aim_point)
	elif event.is_action_pressed("cast_area"):
		request_cast.rpc_id(1, CastMode.AREA, true, _forward())
	elif event.is_action_pressed("cast_self") or _is_middle_click(event):
		request_cast.rpc_id(1, CastMode.SELF, true, _forward())
	elif event.is_action_pressed("cast_weapon"):
		request_weapon.rpc_id(1, _forward())
	elif event.is_action_pressed("cast_special"):
		request_special.rpc_id(1, aim_point)
	elif event.is_action_pressed("class_ability"):
		request_ability.rpc_id(1, _forward())


func _is_middle_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed


func _physics_process(delta: float) -> void:
	if is_local():
		_move_local(delta)
	if multiplayer.is_server():
		_update_host(delta)


func _process(_delta: float) -> void:
	_update_effect_visual()
	_update_body_visual()


# Caído: o corpo deita e fica translúcido até alguém reviver com Vida.
# Invisível (Passo sombrio): quase transparente.
func _update_body_visual() -> void:
	if health.dead != _shown_dead:
		_shown_dead = health.dead
		body.rotation.x = PI / 2.0 if health.dead else 0.0
		body.position.y = 0.5 if health.dead else 1.0
	var alpha := 0.5 if health.dead else (0.8 if invisible > 0.0 else 0.0)
	for part in body_parts:
		part.transparency = alpha


func _move_local(delta: float) -> void:
	if not is_bot:
		_update_aim()
	if health.dead:
		velocity = Vector3.ZERO
		push_velocity = Vector3.ZERO
		return

	# Andar: clicar (ou segurar) no chão leva o personagem até lá pelo navmesh;
	# as teclas de direção (setas) andam direto e cancelam o destino.
	if not is_bot and Input.is_action_pressed("move_to_cursor"):
		set_move_target(aim_point)
	var direction := Vector3.ZERO
	var keys := Vector2.ZERO if is_bot else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keys != Vector2.ZERO:
		has_move_target = false
		direction = Vector3(keys.x, 0.0, keys.y)
	elif has_move_target:
		direction = _path_direction()

	if dash_time > 0.0:
		dash_time -= delta
		velocity = dash_velocity
		move_and_slide()
		return

	var speed: float = cls.speed + speed_bonus
	if health.frozen > 0.0:
		speed = 0.0
	elif health.chilled > 0.0:
		speed *= 0.5
	if fx_shape != SpellResolver.Shape.NONE:
		speed *= 0.4
	direction = direction.normalized()
	velocity.x = direction.x * speed + push_velocity.x
	velocity.z = direction.z * speed + push_velocity.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	push_velocity = push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()
	_check_stuck(delta, direction, speed)

	var flat_aim := Vector3(aim_point.x, global_position.y, aim_point.z)
	if health.frozen <= 0.0 and flat_aim.distance_to(global_position) > 0.1:
		look_at(flat_aim, Vector3.UP)


func set_move_target(point: Vector3) -> void:
	point.y = 0.0
	if has_move_target and point.distance_to(move_target) < 0.2:
		return
	move_target = point
	has_move_target = true
	_stuck_time = 0.0
	nav_agent.target_position = point


# Próximo trecho do caminho. Destino dentro de um obstáculo: para no ponto
# alcançável mais próximo. Navmesh ainda carregando: linha reta.
func _path_direction() -> Vector3:
	var to_target := move_target - global_position
	to_target.y = 0.0
	if to_target.length() <= ARRIVE_DISTANCE:
		has_move_target = false
		return Vector3.ZERO
	if NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) == 0:
		return to_target.normalized()
	var next := nav_agent.get_next_path_position()
	if nav_agent.is_navigation_finished():
		has_move_target = false
		return Vector3.ZERO
	var direction := next - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		direction = to_target
	return direction.normalized()


# Destino dentro de um obstáculo ou atrás de outro personagem: desiste em vez de empurrar parado.
func _check_stuck(delta: float, direction: Vector3, speed: float) -> void:
	if not has_move_target or direction == Vector3.ZERO or speed <= 0.0:
		_stuck_time = 0.0
		return
	if get_real_velocity().length() < speed * 0.2:
		_stuck_time += delta
		if _stuck_time >= STUCK_TIME:
			has_move_target = false
	else:
		_stuck_time = 0.0


func _show_move_marker(at: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.35
	marker.mesh = ring
	marker.material_override = E.make_material(Color(0.4, 1.0, 0.5, 0.8))
	get_parent().add_child(marker)
	marker.global_position = Vector3(at.x, 0.05, at.z)
	get_tree().create_timer(0.35).timeout.connect(marker.queue_free)


func _update_aim() -> void:
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)
	if hit != null:
		aim_point = hit


# --- Empurrão ----------------------------------------------------------------

# Chamado no host. O movimento é do dono, então o empurrão vai para o PC dele.
func push(impulse: Vector3) -> void:
	impulse.y = 0.0
	if is_local():
		_add_push(impulse)
	else:
		receive_push.rpc_id(peer_id, impulse)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_push(impulse: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_add_push(impulse)


func _add_push(impulse: Vector3) -> void:
	push_velocity = (push_velocity + impulse).limit_length(MAX_PUSH)


# --- Pedidos ao host ---------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_element(element: int) -> void:
	if not _from_owner():
		return
	# Um elemento novo interrompe spray/beam/arco e começa outra combinação.
	if _is_channeling():
		_cancel_channel()
	queue.add(element)
	_publish_queue()
	auto_cast_timer = AUTO_CAST_DELAY if not queue.is_empty() else 0.0


@rpc("any_peer", "call_local", "reliable")
func request_cast(mode: int, pressed: bool, aim: Vector3) -> void:
	if not multiplayer.is_server() or _sender() != peer_id:
		return
	# Soltar o botão sempre encerra o feitiço, mesmo se o mago caiu ou congelou.
	if not pressed:
		_set_cast_dir(aim)
		_stop_channel()
		_cast_dir = Vector3.ZERO
		return
	if not _from_owner():
		return
	_set_cast_dir(aim)
	if mode == CastMode.FORWARD:
		_cast_forward()
	elif mode == CastMode.AREA:
		_cast_area()
	elif mode == CastMode.SELF:
		_cast_self()
	_cast_dir = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func request_weapon(aim: Vector3) -> void:
	if not _from_owner() or _is_channeling() or weapon_timer > 0.0:
		return
	_set_cast_dir(aim)
	_swing_weapon()
	_cast_dir = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func request_ability(aim: Vector3) -> void:
	if not _from_owner() or _is_channeling() or ability_cooldown > 0.0:
		return
	_set_cast_dir(aim)
	var used := true
	if cls.ability == "arcane_shield":
		_ability_arcane_shield()
	elif cls.ability == "shadow_step":
		used = _ability_shadow_step()
	elif cls.ability == "charge":
		_ability_charge()
	if used:
		ability_cooldown = cls.ability_cooldown * cooldown_mult
		# Usar uma habilidade também reinicia a espera do disparo automático.
		if not queue.is_empty():
			auto_cast_timer = AUTO_CAST_DELAY
	_cast_dir = Vector3.ZERO


@rpc("any_peer", "call_local", "reliable")
func request_special(target_point: Vector3) -> void:
	if not _from_owner() or _is_channeling():
		return
	var id := Specials.match_special(queue.elements)
	if id.is_empty() or special_cooldowns.get(id, 0.0) > 0.0:
		return
	if _cast_special(id, target_point):
		var cooldowns := special_cooldowns.duplicate()
		cooldowns[id] = Specials.SPECIALS[id].cooldown * cls.special_cooldown * cooldown_mult
		special_cooldowns = cooldowns
		_clear_queue()


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if sender == 0 else sender


# O host só aceita pedidos do dono deste mago, e só se ele puder agir.
func _from_owner() -> bool:
	if not multiplayer.is_server() or health.dead or health.frozen > 0.0:
		return false
	return _sender() == peer_id


# Usa a mira que o dono viu no momento do clique (a rotação sincronizada pode atrasar).
func _set_cast_dir(aim: Vector3) -> void:
	aim.y = 0.0
	if aim.length() > 0.1:
		_cast_dir = aim.normalized()


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
	invisible = 0.0   # atacar revela o Assassino
	var elements := queue.elements.duplicate()
	var shape := SpellResolver.resolve_shape(elements)
	if shape == SpellResolver.Shape.BARRIER:
		_spawn_barrier(global_position + _forward() * 2.5, elements)
		_clear_queue()
		return
	# Projétil carrega enquanto o botão estiver pressionado; spray, beam e arco
	# ficam ativos enquanto ele estiver pressionado.
	channel_elements = elements
	channel_shape = shape
	channel_time = 0.0
	channel_limit = CHANNEL_MAX
	fx_shape = shape
	fx_element = elements[0]
	fx_length = 0.0


func _cast_area() -> void:
	if queue.is_empty() or _is_channeling():
		return
	var elements := queue.elements.duplicate()
	_clear_queue()
	invisible = 0.0
	if E.Type.SHIELD in elements:
		for i in 8:
			var angle := TAU * i / 8.0
			_spawn_barrier(global_position + Vector3(cos(angle), 0.0, sin(angle)) * 3.0, elements)
		return
	var water := elements.count(E.Type.WATER)
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= AREA_RADIUS:
			_hit(target, elements, 1.0)
			if water > 0 and offset.length() > 0.01:
				_push(target, offset.normalized() * AREA_WATER_PUSH * water)
	show_flash.rpc(global_position, AREA_RADIUS, elements[0])


func _cast_self() -> void:
	if queue.is_empty() or _is_channeling():
		return
	var elements := queue.elements.duplicate()
	_clear_queue()
	if E.Type.SHIELD in elements:
		# Escudo sozinho reduz o dano; com outros elementos, protege contra eles.
		var others := elements.filter(func(element): return element != E.Type.SHIELD)
		if others.is_empty():
			health.shielded = Health.SELF_SHIELD_TIME
		else:
			health.set_ward(others)
		return
	health.apply_elements(elements, 1.0)


func _clear_queue() -> void:
	queue.clear()
	_publish_queue()
	auto_cast_timer = 0.0


# Disparo automático (host): a fila vai à frente, na direção em que o
# personagem está virado (que segue o mouse do dono).
func _update_auto_cast(delta: float) -> void:
	if auto_cast_timer <= 0.0:
		return
	auto_cast_timer -= delta
	if auto_cast_timer > 0.0:
		return
	auto_cast_timer = 0.0
	if queue.is_empty() or _is_channeling() or health.dead:
		return
	if health.frozen > 0.0:
		auto_cast_timer = 0.1   # tenta de novo quando descongelar
		return
	var elements := queue.elements.duplicate()
	if SpellResolver.resolve_shape(elements) == SpellResolver.Shape.PROJECTILE:
		# A espera conta como carga: o projétil sai com força total.
		invisible = 0.0
		_fire_projectile(elements, 1.0)
		_clear_queue()
		return
	_cast_forward()
	channel_limit = AUTO_CHANNEL_TIME


# Golpe em cone à frente, com os números da arma da classe. Elementos na fila
# (menos Escudo) vão para a arma e valem por `charges` golpes. Pelas costas
# (ou saindo da invisibilidade) o dano é multiplicado por `backstab`.
func _swing_weapon() -> void:
	var weapon: Dictionary = cls.weapon
	weapon_timer = weapon.cooldown
	if not queue.is_empty():
		var imbue := queue.elements.filter(func(element): return element != E.Type.SHIELD)
		_clear_queue()
		if not imbue.is_empty():
			weapon_elements = imbue
			weapon_charges = weapon.charges
	var elements: Array = weapon_elements if weapon_charges > 0 else []
	var from_shadows := invisible > 0.0
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() > weapon.range or offset.length() < 0.01:
			continue
		if _forward().angle_to(offset.normalized()) >= weapon.angle:
			continue
		var bonus := 1.0
		if not Combat.can_harm(team, target):
			continue
		if from_shadows or _is_behind(target, offset):
			bonus = cls.backstab
		var target_health = target.get_node_or_null("Health")
		if target_health != null:
			target_health.damage(weapon.damage * bonus * power)
			if not elements.is_empty():
				target_health.apply_elements(elements, weapon.element_scale * bonus)
		_push(target, _forward() * weapon.push)
	if weapon_charges > 0:
		weapon_charges -= 1
		if weapon_charges == 0:
			weapon_elements = []
	invisible = 0.0
	show_swing.rpc(elements[0] if not elements.is_empty() else -1, _forward(), weapon.range)


# Atacando pelas costas: o alvo está virado para o mesmo lado do golpe.
func _is_behind(target: Node3D, offset: Vector3) -> bool:
	var facing := -target.global_transform.basis.z
	facing.y = 0.0
	return facing.normalized().dot(offset.normalized()) > 0.5


# --- Habilidades de classe (host) --------------------------------------------

func _ability_arcane_shield() -> void:
	health.shielded = maxf(health.shielded, ARCANE_SHIELD_TIME)
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= ARCANE_SHIELD_RADIUS and offset.length() > 0.01:
			_push(target, offset.normalized() * ARCANE_SHIELD_PUSH)
	show_flash.rpc(global_position, ARCANE_SHIELD_RADIUS, E.Type.SHIELD)


# Avança até 6 m (ou o mais longe que estiver livre) e fica invisível.
func _ability_shadow_step() -> bool:
	for distance in [6.0, 5.0, 4.0, 3.0, 2.0]:
		var destination := _clamp_target(global_position + _forward() * distance, distance)
		if _is_free_spot(destination):
			show_flash.rpc(global_position, 1.0, E.Type.ARCANE)
			do_teleport.rpc_id(peer_id, destination)
			invisible = INVISIBLE_TIME
			return true
	return false


# Corre para a frente; quem estiver no caminho leva dano, os elementos da fila e um empurrão.
func _ability_charge() -> void:
	dash_direction = _forward()
	dash_hit_time = DASH_TIME + 0.1   # folga para a posição sincronizada alcançar
	dash_hit = []
	dash_elements = queue.elements.filter(func(element): return element != E.Type.SHIELD)
	if not queue.is_empty():
		_clear_queue()
	invisible = 0.0
	do_dash.rpc_id(peer_id, dash_direction * DASH_SPEED, DASH_TIME)


func _update_dash_hits(delta: float) -> void:
	if dash_hit_time <= 0.0:
		return
	dash_hit_time -= delta
	for target in _damageables():
		if target in dash_hit or target.global_position.distance_to(global_position) > DASH_HIT_RADIUS:
			continue
		if not Combat.can_harm(team, target):
			continue
		dash_hit.append(target)
		var target_health = target.get_node_or_null("Health")
		if target_health != null:
			target_health.damage(DASH_DAMAGE * power)
			if not dash_elements.is_empty():
				target_health.apply_elements(dash_elements, 1.0)
		var away: Vector3 = target.global_position - global_position
		away.y = 0.0
		_push(target, (dash_direction + away.normalized() * 0.5).normalized() * DASH_PUSH)


@rpc("any_peer", "call_local", "reliable")
func do_dash(dash: Vector3, duration: float) -> void:
	if _sender() != 1:
		return
	dash_velocity = dash
	dash_time = duration


# --- Atualização do host -----------------------------------------------------

func _update_host(delta: float) -> void:
	if moba:
		_update_moba(delta)
	weapon_timer = maxf(weapon_timer - delta, 0.0)
	ability_cooldown = maxf(ability_cooldown - delta, 0.0)
	invisible = maxf(invisible - delta, 0.0)
	_update_dash_hits(delta)
	_update_auto_cast(delta)
	_update_cooldowns(delta)
	_update_storm(delta)
	if _is_channeling():
		if health.frozen > 0.0:
			_stop_channel()
		else:
			_update_channel(delta)


func _update_cooldowns(delta: float) -> void:
	if special_cooldowns.is_empty():
		return
	var cooldowns := {}
	for id in special_cooldowns:
		var left: float = special_cooldowns[id] - delta
		if left > 0.0:
			cooldowns[id] = left
	special_cooldowns = cooldowns


func _update_channel(delta: float) -> void:
	channel_time += delta
	if channel_time >= channel_limit:
		_stop_channel()
		return

	var length := 0.0
	var width := 0.3
	if channel_shape == SpellResolver.Shape.PROJECTILE:
		length = clampf(channel_time / CHARGE_TIME, 0.0, 1.0)
	elif channel_shape == SpellResolver.Shape.SPRAY:
		length = SPRAY_RANGE
		width = 2.0
		var water := channel_elements.count(E.Type.WATER)
		for target in _damageables():
			var offset: Vector3 = target.global_position - global_position
			offset.y = 0.0
			if offset.length() > 0.01 and offset.length() <= SPRAY_RANGE \
					and _forward().angle_to(offset.normalized()) < SPRAY_ANGLE:
				_hit(target, channel_elements, delta)
				if water > 0:
					_push(target, offset.normalized() * SPRAY_WATER_PUSH * water * delta)
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


# Encerra o feitiço contínuo; o projétil carregado é disparado aqui.
func _stop_channel() -> void:
	if not _is_channeling():
		return
	if channel_shape == SpellResolver.Shape.PROJECTILE:
		_fire_projectile(channel_elements, clampf(channel_time / CHARGE_TIME, 0.0, 1.0))
	_cancel_channel()


func _cancel_channel() -> void:
	channel_shape = SpellResolver.Shape.NONE
	channel_elements = []
	fx_shape = SpellResolver.Shape.NONE
	_clear_queue()


func _fire_projectile(elements: Array, charge: float) -> void:
	get_parent().spawn_entity({
		"type": "projectile",
		"pos": global_position + Vector3.UP,
		"dir": _forward(),
		"elements": elements,
		"caster": String(name),
		"team": team,
		"power": lerpf(PROJECTILE_POWER.x, PROJECTILE_POWER.y, charge) * cls.spell_power * power,
		"speed": lerpf(PROJECTILE_SPEED.x, PROJECTILE_SPEED.y, charge),
	})


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


# --- Feitiços especiais (host) -----------------------------------------------

# Devolve false se não deu para lançar (ex.: teleporte para dentro de uma parede).
func _cast_special(id: String, target_point: Vector3) -> bool:
	if id == "meteor":
		get_parent().spawn_entity({"type": "meteor", "team": team, "pos": _clamp_target(target_point, METEOR_RANGE)})
	elif id == "teleport":
		var destination := _clamp_target(target_point, TELEPORT_RANGE)
		if not _is_free_spot(destination):
			return false
		show_flash.rpc(global_position, 1.2, E.Type.ARCANE)
		show_flash.rpc(destination, 1.2, E.Type.ARCANE)
		do_teleport.rpc_id(peer_id, destination)
	elif id == "storm":
		storm_time = STORM_TIME
		storm_tick = 0.0
	elif id == "frost":
		for enemy in _hostile_units(FROST_RADIUS):
			enemy.health.freeze(FROST_TIME)
		show_flash.rpc(global_position, FROST_RADIUS, E.Type.COLD)
	elif id == "blessing":
		for player in get_tree().get_nodes_in_group("players"):
			if Combat.team_of(player) != team:
				continue
			player.health.revive()
			player.health.apply_elements([E.Type.LIFE, E.Type.LIFE], 1.0)
			show_flash.rpc(player.global_position, 1.5, E.Type.LIFE)
	return true


func _update_storm(delta: float) -> void:
	if storm_time <= 0.0:
		return
	storm_time -= delta
	storm_tick -= delta
	if storm_tick > 0.0:
		return
	storm_tick = STORM_INTERVAL
	var targets := _hostile_units(STORM_RANGE)
	if targets.is_empty():
		return
	var target: Node3D = targets.pick_random()
	target.health.apply_elements([E.Type.LIGHTNING, E.Type.LIGHTNING], 1.0)
	show_bolt.rpc(target.global_position)


# Ponto no chão a no máximo `max_range` do mago, dentro da arena.
func _clamp_target(point: Vector3, max_range: float) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() > max_range:
		offset = offset.normalized() * max_range
	var target := global_position + offset
	return Vector3(clampf(target.x, -ARENA_LIMIT, ARENA_LIMIT), 0.0, clampf(target.z, -ARENA_LIMIT, ARENA_LIMIT))


func _is_free_spot(point: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), point + Vector3.UP * 1.05)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


@rpc("any_peer", "call_local", "reliable")
func do_teleport(destination: Vector3) -> void:
	if _sender() != 1:
		return
	global_position = destination
	push_velocity = Vector3.ZERO


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
	if fx_shape == SpellResolver.Shape.PROJECTILE:
		# Carga: a pedra/gelo cresce na frente do mago.
		box.size = Vector3.ONE * (0.25 + 0.45 * fx_length)
		effect_mesh.position = Vector3(0.0, 1.0, -0.9)
	else:
		box.size = Vector3(fx_width, 0.3, maxf(fx_length, 0.01))
		effect_mesh.position = Vector3(0.0, 1.0, -fx_length / 2.0)


# Disco colorido rápido no chão (área, teleporte, bênção, inverno).
@rpc("any_peer", "call_local", "reliable")
func show_flash(at: Vector3, radius: float, element: int) -> void:
	if _sender() != 1:
		return
	var flash := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.05
	flash.mesh = disc
	var color: Color = E.COLORS[element]
	color.a = 0.4
	flash.material_override = E.make_material(color)
	get_parent().add_child(flash)
	flash.global_position = Vector3(at.x, 0.05, at.z)
	get_tree().create_timer(0.3).timeout.connect(flash.queue_free)


@rpc("any_peer", "call_local", "reliable")
func show_swing(element: int, direction: Vector3, weapon_range: float) -> void:
	if _sender() != 1:
		return
	var swing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(weapon_range * 1.2, 0.15, 0.4)
	swing.mesh = box
	var color: Color = E.COLORS[element] if element >= 0 else Color(0.9, 0.9, 0.95)
	color.a = 0.7
	swing.material_override = E.make_material(color)
	get_parent().add_child(swing)
	var center := global_position + direction.normalized() * (weapon_range * 0.6)
	swing.global_position = Vector3(center.x, 1.0, center.z)
	swing.look_at(swing.global_position + direction, Vector3.UP)
	swing.rotate_object_local(Vector3.UP, PI / 2.0)
	get_tree().create_timer(0.12).timeout.connect(swing.queue_free)


@rpc("any_peer", "call_local", "reliable")
func show_bolt(at: Vector3) -> void:
	if _sender() != 1:
		return
	var bolt := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 12.0, 0.25)
	bolt.mesh = box
	bolt.material_override = E.make_material(E.COLORS[E.Type.LIGHTNING])
	get_parent().add_child(bolt)
	bolt.global_position = Vector3(at.x, 6.0, at.z)
	get_tree().create_timer(0.15).timeout.connect(bolt.queue_free)


# --- Utilidades (host) -------------------------------------------------------

# Tudo que tem vida, menos o próprio personagem. Quem pode ser atingido
# depende do modo (ver combat.gd): na Arena há fogo amigo; no MOBA, não.
func _damageables() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("damageable"):
		if node != self and node is Node3D and not node.is_queued_for_deletion():
			result.append(node)
	return result


# Unidades hostis vivas (sem estruturas) num raio, para Tempestade e Inverno.
func _hostile_units(radius: float) -> Array:
	return _damageables().filter(func(node): return Combat.is_hostile(team, Combat.team_of(node)) \
		and not node.is_in_group("structures") and not node.health.dead \
		and node.global_position.distance_to(global_position) <= radius)


# Feitiços (spray, beam, arco, área): a força depende da classe.
func _hit(target: Node, elements: Array, scale: float) -> void:
	var target_health := target.get_node_or_null("Health")
	if target_health == null:
		return
	elements = Combat.filter_elements(team, target, elements)
	if not elements.is_empty():
		target_health.apply_elements(elements, scale * cls.spell_power * power)


func _push(target: Node, impulse: Vector3) -> void:
	if target.has_method("push") and Combat.can_harm(team, target):
		target.push(impulse)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_barrier(at: Vector3, elements: Array) -> void:
	var offset := at - global_position
	get_parent().spawn_entity({
		"type": "barrier",
		"pos": Vector3(at.x, 0.0, at.z),
		"yaw": atan2(offset.x, offset.z),
		"elements": elements,
		"team": team,
	})


# --- MOBA (host) -------------------------------------------------------------

func _update_moba(delta: float) -> void:
	if health.dead:
		respawn_time -= delta
		if respawn_time <= 0.0:
			_respawn()
		return
	_gold_fraction += Progression.PASSIVE_GOLD * delta
	if _gold_fraction >= 1.0:
		gold += int(_gold_fraction)
		_gold_fraction -= int(_gold_fraction)
	if not buffs.is_empty():
		var left := {}
		for id in buffs:
			if buffs[id] - delta > 0.0:
				left[id] = buffs[id] - delta
		var expired := left.size() != buffs.size()
		buffs = left
		if expired:
			_recompute_stats()


func add_rewards(gold_gain: int, xp_gain: int) -> void:
	gold += gold_gain
	var result := Progression.apply_xp(level, xp, xp_gain)
	var leveled: bool = result[0] != level
	level = result[0]
	xp = result[1]
	if leveled:
		_recompute_stats()
		show_flash.rpc(global_position, 1.5, E.Type.LIFE)


func add_buff(id: String) -> void:
	var updated := buffs.duplicate()
	updated[id] = Progression.BUFFS[id].duration
	buffs = updated
	_recompute_stats()


# Classe + nível + itens + bônus. Ao ganhar vida máxima, ganha também a vida atual.
func _recompute_stats() -> void:
	var stats := Progression.stats(cls, level, items, buffs)
	var gained: float = stats.max_hp - health.max_hp
	health.max_hp = stats.max_hp
	if not health.dead:
		health.hp = clampf(health.hp + maxf(gained, 0.0), 0.0, health.max_hp)
	health.armor = stats.armor
	power = stats.power
	speed_bonus = stats.speed
	cooldown_mult = stats.cooldown


func is_at_shop() -> bool:
	return health.dead or global_position.distance_to(MobaMap.fountain(team)) \
		<= MobaMap.FOUNTAIN_RADIUS + Progression.SHOP_EXTRA_RANGE


@rpc("any_peer", "call_local", "reliable")
func request_buy(item_id: String) -> void:
	if not moba or not multiplayer.is_server() or _sender() != peer_id:
		return
	if not Progression.cannot_buy(item_id, gold, items, is_at_shop()).is_empty():
		return
	gold -= Progression.ITEMS[item_id].cost
	var updated := items.duplicate()
	updated.append(item_id)
	items = updated
	_recompute_stats()


func _respawn() -> void:
	respawn_time = 0.0
	health.reset()
	_recompute_stats()
	health.hp = health.max_hp
	var spot := MobaMap.spawn_point(team, color_index)
	do_teleport.rpc_id(peer_id, spot)


func _on_died() -> void:
	if moba:
		respawn_time = Progression.respawn_time(level)
	_cancel_channel()
	storm_time = 0.0
	invisible = 0.0
	dash_hit_time = 0.0
