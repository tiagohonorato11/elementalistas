# Personagem jogável (Mago, Assassino ou Lutador — ver scripts/core/classes.gd).
# Cada jogador escolhe 3 elementos antes da partida (D F G). Eles formam uma carga
# de até 3 que a próxima skill (Q W E R) usa e consome. Skills gastam mana e têm recarga.
# Em rede:
# - o dono (peer_id) controla movimento e mira, sincronizados para todos;
# - teclas de elemento e de skill viram pedidos (RPC) para o host;
# - o host roda a carga, as skills e o dano, e sincroniza vida/carga/mana/efeitos.
extends CharacterBody3D

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Classes = preload("res://scripts/core/classes.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const BotBrain = preload("res://scripts/moba/bot_brain.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const SpellFx = preload("res://scripts/vfx/spell_fx.gd")
const StatusFx = preload("res://scripts/vfx/status_fx.gd")
const UnitModel = preload("res://scripts/vfx/unit_model.gd")
const HealthBar = preload("res://scripts/vfx/health_bar.gd")
const UnitSounds = preload("res://scripts/audio/unit_sounds.gd")

# Animação de golpe de cada classe (modelos KayKit).
const MELEE_ANIMS := {
	"mage": "1H_Melee_Attack_Chop", "assassin": "Dualwield_Melee_Attack_Stab", "fighter": "2H_Melee_Attack_Chop",
}
# Animação de cada skill.
const SKILL_ANIMS := {
	"orb": "Spellcast_Shoot", "bless_curse": "Spellcast_Raise", "mini_meteor": "Spellcast_Long",
	"dagger": "Throw", "veil_mark": "Spellcast_Raise", "shadow_step": "Dodge_Forward",
	"whirl": "2H_Melee_Attack_Spin", "shout": "Spellcast_Raise", "charge": "2H_Melee_Attack_Spin",
	"ultimate": "Spellcast_Long",
}
const Health = preload("res://scripts/core/health.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")

const GRAVITY := 20.0
# Andar clicando.
const ARRIVE_DISTANCE := 0.3
const STUCK_TIME := 0.4
const PLAYER_COLORS := [Color(0.3, 0.35, 0.9), Color(0.25, 0.75, 0.35), Color(0.9, 0.55, 0.15), Color(0.65, 0.3, 0.85)]

# Skills: alvo do W (unidade sob o mouse), mana e Investida.
const HOVER_RADIUS := 1.5        # distância do cursor até a unidade
const TARGET_RANGE := 10.0       # alcance do W
const FOUNTAIN_MANA_MULT := 6.0  # regeneração de mana na fonte do MOBA
const DASH_TIME := 0.35
const DASH_SPEED := 20.0         # 20 m/s por 0,35 s = 7 m
const DASH_HIT_RADIUS := 1.6
const GRAVITY_PULL := 7.0        # puxão por Gravidade na carga
const BLIND_FACTOR := 0.5        # cego (Fumaça): metade do dano
const BLOOD_STEAL := 0.25        # Sangue na carga: rouba 25% do dano causado (por Sangue)
const LIFESTEAL_BUFF := 0.2      # Sangue em si mesmo/aliado: roubo de vida de 20% (por Sangue)
const LIFESTEAL_TIME := 6.0
const SELF_HEAL := 30.0          # Vida no W (Assassino: sempre nele mesmo)
const SELF_BARRIER := 40.0       # Escudo no W: barreira (por Escudo)
const SELF_BARRIER_TIME := 5.0
const HOLD_SLOW := 0.5           # segurando o W (Mago): anda mais devagar
const BUBBLE_TICK := 0.25
const BUBBLE_STRENGTH := 0.15    # força dos elementos da bolha nos inimigos dentro, por pulso
const BUBBLE_EARTH_BONUS := 40.0
const BUBBLE_HEAL := 8.0         # Vida na bolha: cura por segundo
const BUBBLE_PUSH := 6.0
# Elementos que na bolha têm efeito próprio (os outros atingem os inimigos dentro).
const BUBBLE_SPECIAL := [E.Type.LIFE, E.Type.WATER, E.Type.SMOKE, E.Type.BLOOD, E.Type.SHIELD,
	E.Type.EARTH, E.Type.ARCANE, E.Type.VOID, E.Type.GRAVITY]

# Empurrão.
const PUSH_DECAY := 18.0
const MAX_PUSH := 12.0

# Ultimates.
const METEOR_RANGE := 14.0
const STORM_TIME := 5.0
const STORM_INTERVAL := 0.5
const STORM_RANGE := 14.0
const FROST_RADIUS := 10.0
const FROST_TIME := 3.5
const QUAKE_RADIUS := 7.0
const QUAKE_DAMAGE := 60.0
const QUAKE_STUN := 1.5
const CATACLYSM_RANGE := 14.0
const CATACLYSM_RADIUS := 4.0
const CATACLYSM_DAMAGE := 120.0
const CATACLYSM_DELAY := 1.0
const TIDE_RANGE := 9.0
const TIDE_ANGLE := 0.8          # ~45 graus
const TIDE_PUSH := 14.0
const FORTRESS_RADIUS := 8.0
const FORTRESS_SHIELD := 5.0
const ECLIPSE_RADIUS := 9.0
const ECLIPSE_DAMAGE := 30.0
const SINGULARITY_RANGE := 14.0
const SINGULARITY_RADIUS := 8.0
const SINGULARITY_DAMAGE := 40.0
const SINGULARITY_STUN := 1.0
const SMOKESCREEN_RADIUS := 8.0
const SMOKESCREEN_HIDE := 3.0
const ZONE_RADIUS := 4.0         # zona dos elementos secundários do ultimate
const ZONE_TIME := 3.0
const BLOOD_MOON_RADIUS := 9.0
const BLOOD_MOON_DAMAGE := 35.0
# MEGA (3 elementos iguais).
const RAIN_METEORS := 5
const RAIN_SPREAD := 5.0
const RAIN_DELAY := 0.3
const MEGA_STORM_TIME := 8.0
const MEGA_STORM_INTERVAL := 0.3
const MEGA_STORM_CHAIN := 2
const ICE_AGE_RADIUS := 15.0
const ICE_AGE_FREEZE := 3.0
const FISSURE_LENGTH := 16.0
const FISSURE_WIDTH := 2.0
const FISSURE_DAMAGE := 100.0
const FISSURE_STUN := 2.0
const SUPERNOVA_DELAY := 1.5
const SUPERNOVA_RADIUS := 10.0
const SUPERNOVA_DAMAGE := 180.0
const TSUNAMI_RANGE := 18.0
const TSUNAMI_ANGLE := 1.3
const TSUNAMI_DAMAGE := 30.0
const BASTION_RADIUS := 10.0
const BASTION_TIME := 3.0
const BLACKOUT_RADIUS := 12.0
const BLACKOUT_TIME := 3.0
const BLACK_HOLE_RADIUS := 10.0
const BLACK_HOLE_TIME := 4.0
const BLACK_HOLE_DPS := 25.0
const MEGA_SMOKE_RADIUS := 12.0
const FEAST_RADIUS := 10.0
const FEAST_DAMAGE := 50.0
const FEAST_BLEED := 6.0
const FEAST_TEAM_STEAL := 0.3

# Ações configuráveis (ver scripts/ui/keybinds.gd).
const CHARGE_ACTIONS := ["charge_1", "charge_2", "charge_3"]
const SKILL_ACTIONS := {"skill_q": "q", "skill_w": "w", "skill_e": "e", "skill_r": "r"}

var peer_id := 1               # dono do personagem (bots: o host)
var team := Combat.BLUE
var is_bot := false            # controlado pela IA no host (ver bot_brain.gd)
var color_index := 0
var power := 1.0               # multiplicador de dano (níveis, itens e bônus no MOBA)
var class_id := Classes.DEFAULT
var cls: Dictionary          # dados da classe (classes.gd)
var elements: Array = []     # os 3 elementos escolhidos no lobby (D F G)
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
var queue_view: Array = []        # carga atual (até 3 elementos)
var fx_shape: int = SpellResolver.Shape.NONE
var fx_element := 0
var fx_elements: Array = []   # elementos do feitiço contínuo (para os efeitos visuais)
var fx_length := 0.0   # comprimento do efeito (raio laser)
var fx_width := 0.3
var mana := 0.0
var max_mana := 0.0
var skill_cooldowns := {}         # "q"/"w"/"e"/"r" -> segundos restantes
var invisible := 0.0              # Véu/Passo sombrio: os inimigos ignoram
var bubble_time := 0.0            # bolha de escudo do Mago (W segurado)
var bubble_elements: Array = []

# Só usados no host.
var queue := ElementQueue.new()
var channel_elements: Array = []
var channel_shape: int = SpellResolver.Shape.NONE
var channel_time := 0.0
var channel_limit := 0.0
var channel_dps := 0.0
var channel_range := 0.0
var weapon_timer := 0.0
var storm_time := 0.0
var storm_tick := 0.0
var storm_elements: Array = []
var storm_scale := 1.0
var storm_interval := STORM_INTERVAL
var storm_chain := 0              # Tempestade suprema: raios que saltam
var _bubble_tick := 0.0
var _bubble_mesh: MeshInstance3D
var _bubble_shown: Array = []
var _hold_slot := ""              # skill segurada (dono): decide ao soltar ou ao completar
var _hold_time := 0.0
var dash_hit_time := 0.0      # Investida em andamento (host)
var dash_direction := Vector3.ZERO
var dash_elements: Array = []
var dash_damage := 0.0
var dash_push := 0.0
var dash_hit: Array = []
var _cast_dir := Vector3.ZERO   # direção enviada pelo dono no pedido

# Investida: o dono move o personagem (só no PC dele).
var dash_velocity := Vector3.ZERO
var dash_time := 0.0

# Andar clicando (só no PC do dono).
var nav_agent: NavigationAgent3D
var move_target := Vector3.ZERO
var has_move_target := false
var _stuck_time := 0.0

var unit_model: Node3D
# Ação pontual para a animação (golpe, tiro, feitiço), sincronizada pelo host.
var action_anim := ""
var action_count := 0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("players")
	cls = Classes.info(class_id)
	elements = Loadout.sanitize(elements, class_id)
	moba = Network.game_mode() == "moba"
	_build_body()

	health = Health.new()
	health.name = "Health"
	health.max_hp = cls.hp
	health.armor = cls.armor
	# Arena: caído espera um aliado com Vida. MOBA: volta sozinho na base.
	health.revivable = not moba
	add_child(health)
	max_mana = cls.mana
	mana = max_mana
	if multiplayer.is_server():
		health.died.connect(_on_died)
		if moba:
			_recompute_stats()
			mana = max_mana

	add_child(SpellFx.new())
	var status_fx := StatusFx.new()
	status_fx.height = 2.0
	add_child(status_fx)
	var bar := HealthBar.new()
	bar.width = 1.4
	bar.height_above = 2.35
	add_child(bar)

	SyncUtil.add_sync(self, "MoveSync", peer_id, [".:position", ".:rotation"])
	SyncUtil.add_sync(self, "StateSync", 1, [
		".:queue_view", ".:fx_shape", ".:fx_element", ".:fx_elements", ".:fx_length", ".:fx_width",
		".:mana", ".:max_mana", ".:skill_cooldowns", ".:invisible", ".:action_anim", ".:action_count",
		".:bubble_time", ".:bubble_elements",
		"Health:hp", "Health:wet", "Health:burning", "Health:chilled", "Health:shielded", "Health:dead",
		"Health:frozen", "Health:ward", "Health:ward_elements", "Health:max_hp",
		"Health:stunned", "Health:slowed", "Health:slow_amount", "Health:hasted", "Health:haste_amount",
		"Health:vulnerable", "Health:fortified", "Health:blinded", "Health:blackout", "Health:bleeding",
		"Health:lifesteal", "Health:barrier_hp", "Health:silenced",
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


# Modelo animado da classe (KayKit), com um anel no chão na cor do jogador
# (Arena) ou do time (MOBA) e o nome da classe acima da cabeça.
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

	unit_model = UnitModel.new()
	unit_model.model_id = class_id
	unit_model.unit_height = 2.0
	add_child(unit_model)

	var color: Color = PLAYER_COLORS[color_index % PLAYER_COLORS.size()]
	if moba:
		color = Combat.TEAM_COLORS[team]
	Vfx.add_ring(self, color, radius + 0.35)

	var label := Label3D.new()
	label.text = cls.label
	label.font_size = 28
	label.outline_size = 6
	label.modulate = color.lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.75
	add_child(label)

	var sounds := UnitSounds.new()
	sounds.material = "flesh"
	sounds.footsteps = true
	sounds.is_local = is_local() and not is_bot
	add_child(sounds)


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


# --- Entrada (só no PC do dono) ---------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_bot or not is_local() or health.dead:
		return
	for slot in CHARGE_ACTIONS.size():
		if event.is_action_pressed(CHARGE_ACTIONS[slot]):
			request_charge.rpc_id(1, slot)
			return
	for action in SKILL_ACTIONS:
		var slot: String = SKILL_ACTIONS[action]
		if event.is_action_pressed(action):
			if Classes.skill(class_id, slot).has("hold"):
				# Segurável (W do Mago): toque rápido ou segurar até completar.
				_hold_slot = slot
				_hold_time = 0.0
			else:
				request_skill.rpc_id(1, slot, aim_point, hover_target_name())
			return
		if event.is_action_released(action) and slot == _hold_slot:
			_release_hold(false)
			return
	if event.is_action_pressed("move_to_cursor"):
		_show_move_marker(aim_point)
	elif event.is_action_pressed("cast_weapon"):
		request_weapon.rpc_id(1, _forward_to(aim_point))


# Nome da unidade sob o mouse (alvo do W), ou "" se não houver nenhuma.
# Aliados caídos contam (o W os levanta); estruturas não.
func hover_target_name() -> String:
	var best := ""
	var best_distance := HOVER_RADIUS
	for node in get_tree().get_nodes_in_group("damageable"):
		if node.is_in_group("structures") or node.is_queued_for_deletion():
			continue
		if node.health.dead and not node.is_in_group("players"):
			continue
		var offset: Vector3 = node.global_position - aim_point
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = String(node.name)
	return best


func _physics_process(delta: float) -> void:
	if is_local():
		_move_local(delta)
	if multiplayer.is_server():
		_update_host(delta)


func _process(delta: float) -> void:
	_update_body_visual()
	_update_bubble_visual()
	if not _hold_slot.is_empty():
		_hold_time += delta
		if _hold_time >= Classes.skill(class_id, _hold_slot).hold:
			_release_hold(true)


# Soltou (toque: skill normal) ou completou o tempo (versão segurada).
func _release_hold(held: bool) -> void:
	var slot := _hold_slot
	_hold_slot = ""
	_hold_time = 0.0
	if health.dead:
		return
	if held:
		request_skill_held.rpc_id(1, slot, aim_point, hover_target_name())
	else:
		request_skill.rpc_id(1, slot, aim_point, hover_target_name())


# 0 a 1 enquanto segura uma skill (barra no HUD); 0 sem segurar.
func hold_progress() -> float:
	if _hold_slot.is_empty():
		return 0.0
	return clampf(_hold_time / Classes.skill(class_id, _hold_slot).hold, 0.0, 1.0)


# Bolha de escudo: esfera em volta do Mago, na cor dos elementos.
func _update_bubble_visual() -> void:
	var active := bubble_time > 0.0 and not health.dead
	if active and _bubble_mesh == null:
		_bubble_mesh = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = Classes.skill(class_id, "w").get("bubble_radius", 3.0)
		sphere.height = sphere.radius * 2.0
		_bubble_mesh.mesh = sphere
		add_child(_bubble_mesh)
	if _bubble_mesh == null:
		return
	if active and bubble_elements != _bubble_shown:
		_bubble_shown = bubble_elements.duplicate()
		var look := bubble_elements if not bubble_elements.is_empty() else [E.Type.SHIELD]
		_bubble_mesh.material_override = Vfx.glow_material(Vfx.mix_color(look), 0.8, 0.16)
	_bubble_mesh.visible = active


# Invisível (Passo sombrio): quase transparente. Caído: a animação de queda.
func _update_body_visual() -> void:
	unit_model.set_alpha(0.8 if invisible > 0.0 and not health.dead else 0.0)


# Host: dispara uma animação pontual em todos os PCs.
func _act(animation: String) -> void:
	action_anim = animation
	action_count += 1


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

	var speed: float = (cls.speed + speed_bonus) * health.speed_factor()
	if fx_shape != SpellResolver.Shape.NONE:
		speed *= 0.4
	if not _hold_slot.is_empty():
		speed *= HOLD_SLOW
	direction = direction.normalized()
	velocity.x = direction.x * speed + push_velocity.x
	velocity.z = direction.z * speed + push_velocity.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	push_velocity = push_velocity.move_toward(Vector3.ZERO, PUSH_DECAY * delta)
	move_and_slide()
	_check_stuck(delta, direction, speed)

	var flat_aim := Vector3(aim_point.x, global_position.y, aim_point.z)
	if not health.is_disabled() and flat_aim.distance_to(global_position) > 0.1:
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

# Soma o elemento do slot (0 = D, 1 = F, 2 = G) na carga.
@rpc("any_peer", "call_local", "reliable")
func request_charge(slot: int) -> void:
	if not _from_owner() or slot < 0 or slot >= elements.size():
		return
	queue.add(elements[slot])
	_publish_queue()


@rpc("any_peer", "call_local", "reliable")
func request_weapon(aim: Vector3) -> void:
	if not _from_owner() or _is_channeling() or weapon_timer > 0.0:
		return
	_set_cast_dir(aim)
	_swing_weapon()
	_cast_dir = Vector3.ZERO


# Usa a skill do slot ("q", "w", "e", "r") mirando em `aim_point` (chão sob o mouse).
# `target_name`: unidade sob o mouse (para o W). Gasta mana, entra em recarga e consome a carga.
@rpc("any_peer", "call_local", "reliable")
func request_skill(slot: String, aim_point_seen: Vector3, target_name: String) -> void:
	_try_skill(slot, aim_point_seen, target_name, false)


# Versão segurada da skill (W do Mago segurado 1,5 s: bolha de escudo).
@rpc("any_peer", "call_local", "reliable")
func request_skill_held(slot: String, aim_point_seen: Vector3, target_name: String) -> void:
	if Classes.skill(class_id, slot).has("hold"):
		_try_skill(slot, aim_point_seen, target_name, true)


func _try_skill(slot: String, aim_point_seen: Vector3, target_name: String, held: bool) -> void:
	if not _from_owner() or _is_channeling() or health.silenced > 0.0:
		return
	var skill := Classes.skill(class_id, slot)
	if skill.is_empty() or skill_cooldowns.get(slot, 0.0) > 0.0 or mana < skill.cost:
		return
	var charge := queue.elements.duplicate()
	if slot == "r" and charge.is_empty():
		return
	_set_cast_dir(_forward_to(aim_point_seen))
	var target := _skill_target(target_name)
	invisible = 0.0   # agir revela (o Véu em si mesmo volta a esconder)
	if not _use_skill(skill, charge, aim_point_seen, target, held):
		_cast_dir = Vector3.ZERO
		return
	mana -= skill.cost
	var cooldowns := skill_cooldowns.duplicate()
	cooldowns[slot] = skill.cooldown * cooldown_mult
	skill_cooldowns = cooldowns
	_clear_queue()
	_act(SKILL_ANIMS.get(skill.id, "Spellcast_Raise"))
	_cast_dir = Vector3.ZERO


# Alvo do W conferido no host: perto do personagem e (se não for jogador) vivo.
func _skill_target(target_name: String) -> Node3D:
	if target_name.is_empty():
		return null
	var node := get_parent().get_node_or_null(target_name) as Node3D
	if node == null or not node.is_in_group("damageable") or node.is_in_group("structures"):
		return null
	if node.global_position.distance_to(global_position) > TARGET_RANGE:
		return null
	if node.health.dead and not node.is_in_group("players"):
		return null
	return node


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if sender == 0 else sender


# O host só aceita pedidos do dono deste mago, e só se ele puder agir.
func _from_owner() -> bool:
	if not multiplayer.is_server() or health.dead or health.is_disabled():
		return false
	return _sender() == peer_id


# Usa a mira que o dono viu no momento do clique (a rotação sincronizada pode atrasar).
func _set_cast_dir(aim: Vector3) -> void:
	aim.y = 0.0
	if aim.length() > 0.1:
		_cast_dir = aim.normalized()


func _publish_queue() -> void:
	queue_view = queue.elements.duplicate()


# --- Direção (host) ----------------------------------------------------------

func _forward() -> Vector3:
	if _cast_dir != Vector3.ZERO:
		return _cast_dir
	return -global_transform.basis.z


# Direção do personagem até um ponto no chão.
func _forward_to(point: Vector3) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	return offset.normalized() if offset.length() > 0.1 else -global_transform.basis.z


func _is_channeling() -> bool:
	return channel_shape != SpellResolver.Shape.NONE


func _clear_queue() -> void:
	queue.clear()
	_publish_queue()


# Elemento para a cor dos efeitos: o 1º da carga, ou `fallback` sem carga.
func _look(charge: Array, fallback: int) -> int:
	return charge[0] if not charge.is_empty() else fallback


# Golpe básico em cone à frente, com os números da arma da classe. Não usa a carga.
# Pelas costas (ou saindo da invisibilidade) o dano é multiplicado por `backstab`.
func _swing_weapon() -> void:
	var weapon: Dictionary = cls.weapon
	weapon_timer = weapon.cooldown
	var from_shadows := invisible > 0.0
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() > weapon.range or offset.length() < 0.01:
			continue
		if _forward().angle_to(offset.normalized()) >= weapon.angle:
			continue
		if not Combat.can_harm(team, target):
			continue
		var bonus := 1.0
		if from_shadows or _is_behind(target, offset):
			bonus = cls.backstab
		var target_health = target.get_node_or_null("Health")
		if target_health != null:
			drain(target_health.damage(weapon.damage * bonus * _might()), [])
		_push(target, _forward() * weapon.push)
	invisible = 0.0
	show_swing.rpc(-1, _forward(), weapon.range)
	_act(MELEE_ANIMS.get(class_id, "1H_Melee_Attack_Chop"))


# Atacando pelas costas: o alvo está virado para o mesmo lado do golpe.
func _is_behind(target: Node3D, offset: Vector3) -> bool:
	var facing := -target.global_transform.basis.z
	facing.y = 0.0
	return facing.normalized().dot(offset.normalized()) > 0.5


# --- Skills (host) ----------------------------------------------------------
# Cada uma devolve false se não deu para usar (aí não gasta mana nem recarga).

func _use_skill(skill: Dictionary, charge: Array, point: Vector3, target: Node3D, held := false) -> bool:
	match skill.id:
		"orb":
			_fire_projectile(charge, skill.damage, skill.speed, "orb", 1.0, skill.get("splash", 0.0))
		"dagger":
			_fire_projectile(charge, skill.damage, skill.speed, "dagger", cls.backstab)
		"mini_meteor":
			_mini_meteor(skill, charge, point)
		"bless_curse", "veil_mark", "shout":
			if held:
				_bubble(skill, charge)
			else:
				_support_skill(skill, charge, target)
		"shadow_step":
			return _shadow_step(skill, charge)
		"whirl":
			_whirl(skill, charge)
		"charge":
			_dash(skill, charge)
		"ultimate":
			return _cast_ultimate(Ultimates.resolve(charge), charge, point, skill.power)
	return true


# Dano direto da skill (só em quem pode ser ferido) + os elementos da carga.
# Devolve o dano causado; Sangue na carga (ou o bônus de roubo de vida) cura quem lançou.
func _strike(target: Node, damage: float, charge: Array, scale := 1.0) -> float:
	var target_health = target.get_node_or_null("Health")
	if target_health == null:
		return 0.0
	var dealt := 0.0
	if damage > 0.0 and Combat.can_harm(team, target):
		dealt += target_health.damage(damage * cls.spell_power * _might() * scale)
	dealt += _hit(target, charge, scale)
	drain(dealt, charge)
	return dealt


# Roubo de vida (host): 25% do dano por Sangue nos elementos + o bônus de roubo de vida.
# Chamado também por projéteis, meteoros e zonas deste personagem.
func drain(dealt: float, used_elements: Array) -> void:
	if dealt <= 0.0 or health.dead or not multiplayer.is_server():
		return
	var fraction := BLOOD_STEAL * used_elements.count(E.Type.BLOOD)
	if health.lifesteal > 0.0:
		fraction += health.lifesteal_amount
	if fraction > 0.0:
		health.heal(dealt * fraction)


func _is_enemy(node: Node) -> bool:
	return Combat.is_hostile(team, Combat.team_of(node))


# W: no inimigo sob o mouse, enfraquece; em aliado (ou em si mesmo), fortalece.
# Aliado caído: o W o levanta (Arena).
func _support_skill(skill: Dictionary, charge: Array, target: Node3D) -> void:
	if target != null and _is_enemy(target):
		var target_health: Health = target.health
		var for_target := charge
		if skill.id == "veil_mark":
			# Assassino: Vida e Escudo no W são sempre para ele mesmo.
			var own := charge.filter(func(element): return element == E.Type.LIFE or element == E.Type.SHIELD)
			for_target = charge.filter(func(element): return not (element in own))
			_self_elements(health, own)
		_strike(target, 0.0, for_target)
		if skill.has("slow"):
			target_health.slow(skill.slow, skill.duration)
		if skill.has("vulnerable"):
			target_health.make_vulnerable(skill.vulnerable, skill.duration)
		show_flash.rpc(target.global_position, 1.3, _look(charge, E.Type.ARCANE))
		return
	var ally: Node3D = target if target != null else self
	var ally_health: Health = ally.health
	if ally_health.dead:
		ally_health.revive()
	ally_health.heal(skill.get("heal", 0.0) * power)
	_self_elements(ally_health, charge)
	var ward := charge.filter(func(element): return not (element in [E.Type.LIFE, E.Type.SHIELD, E.Type.BLOOD]))
	if not ward.is_empty():
		ally_health.set_ward(ward)
	if skill.id == "veil_mark" and ally.get("invisible") != null:
		ally.invisible = skill.invisible
	if skill.id == "shout":
		ally_health.haste(skill.haste, skill.duration)
		ally_health.fortify(skill.fortify, skill.duration)
	show_flash.rpc(ally.global_position, 1.3, _look(charge, E.Type.LIFE))


# Elementos do W em quem recebe (aliado ou o próprio): Vida cura, Escudo dá
# barreira e Sangue dá roubo de vida.
func _self_elements(target_health: Health, charge: Array) -> void:
	var life := charge.count(E.Type.LIFE)
	if life > 0:
		target_health.heal(SELF_HEAL * life * power)
	var shield := charge.count(E.Type.SHIELD)
	if shield > 0:
		target_health.add_barrier(SELF_BARRIER * shield * power, SELF_BARRIER_TIME)
	var blood := charge.count(E.Type.BLOOD)
	if blood > 0:
		target_health.lifesteal_buff(LIFESTEAL_BUFF * blood, LIFESTEAL_TIME)


# Mini meteoro (E do Mago): cai no cursor e deixa a zona dos elementos da carga.
func _mini_meteor(skill: Dictionary, charge: Array, point: Vector3) -> void:
	get_parent().spawn_entity({"type": "meteor", "team": team, "pos": _clamp_target(point, skill.range),
		"mini": true, "elements": charge, "damage": skill.damage, "radius": skill.radius,
		"zone_time": skill.zone_time, "caster": String(name), "strength": cls.spell_power * _might()})


# Bolha de escudo (W do Mago segurado): barreira no Mago e nos aliados perto;
# a carga dá um poder à bolha enquanto ela dura (ver _update_bubble).
func _bubble(skill: Dictionary, charge: Array) -> void:
	var duration: float = skill.bubble_time * (2.0 if E.Type.SHIELD in charge else 1.0)
	var absorb: float = (skill.barrier + BUBBLE_EARTH_BONUS * charge.count(E.Type.EARTH)) * power
	bubble_elements = charge.duplicate()
	bubble_time = duration
	_bubble_tick = 0.0
	for ally in _bubble_units(skill.bubble_radius, true):
		ally.health.add_barrier(absorb, duration)
	show_flash.rpc(global_position, skill.bubble_radius, _look(charge, E.Type.SHIELD))


# Unidades vivas dentro da bolha: aliadas (com o próprio Mago) ou hostis.
func _bubble_units(radius: float, allies: bool) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("damageable"):
		if node.is_queued_for_deletion() or node.is_in_group("structures") or node.health.dead:
			continue
		if node.global_position.distance_to(global_position) > radius:
			continue
		var ally: bool = node == self or Combat.team_of(node) == team
		if ally == allies and (allies or Combat.is_hostile(team, Combat.team_of(node))):
			result.append(node)
	return result


func _update_bubble(delta: float) -> void:
	if bubble_time <= 0.0:
		return
	bubble_time = maxf(bubble_time - delta, 0.0)
	if bubble_time <= 0.0:
		bubble_elements = []
		return
	var radius: float = Classes.skill(class_id, "w").get("bubble_radius", 3.0)
	# Projéteis inimigos que entram: Arcano reflete; Vazio e Escudo apagam.
	var reflects := E.Type.ARCANE in bubble_elements
	if reflects or E.Type.VOID in bubble_elements or E.Type.SHIELD in bubble_elements:
		for projectile in get_tree().get_nodes_in_group("projectiles"):
			if projectile.is_queued_for_deletion() or not Combat.is_hostile(team, projectile.team):
				continue
			var offset: Vector3 = projectile.global_position - global_position
			offset.y = 0.0
			if offset.length() > radius:
				continue
			if reflects:
				projectile.reflect(team, String(name))
			else:
				projectile.queue_free()
	_bubble_tick -= delta
	if _bubble_tick > 0.0:
		return
	_bubble_tick = BUBBLE_TICK
	for ally in _bubble_units(radius, true):
		if E.Type.LIFE in bubble_elements:
			ally.health.heal(BUBBLE_HEAL * bubble_elements.count(E.Type.LIFE) * BUBBLE_TICK * power)
		if E.Type.WATER in bubble_elements:
			ally.health.burning = 0.0
			ally.health.blinded = 0.0
			ally.health.bleeding = 0.0
		if E.Type.SMOKE in bubble_elements and ally.get("invisible") != null:
			ally.invisible = maxf(ally.invisible, BUBBLE_TICK + 0.3)
		if E.Type.BLOOD in bubble_elements:
			ally.health.lifesteal_buff(LIFESTEAL_BUFF * bubble_elements.count(E.Type.BLOOD), BUBBLE_TICK + 0.3)
	var offensive := bubble_elements.filter(func(element): return not (element in BUBBLE_SPECIAL))
	for enemy in _bubble_units(radius, false):
		if not offensive.is_empty():
			_strike(enemy, 0.0, offensive, BUBBLE_STRENGTH)
		if E.Type.GRAVITY in bubble_elements:
			var away: Vector3 = enemy.global_position - global_position
			away.y = 0.0
			if away.length() > 0.01:
				_push(enemy, away.normalized() * BUBBLE_PUSH)


# Salta até `distance` m para o mouse (ou o mais longe que estiver livre) e
# solta a carga numa área pequena onde cai.
func _shadow_step(skill: Dictionary, charge: Array) -> bool:
	var steps := 5
	for i in steps:
		var distance: float = skill.distance * (1.0 - 0.15 * i)
		var destination := _clamp_target(global_position + _forward() * distance, distance)
		if not _is_free_spot(destination):
			continue
		show_flash.rpc(global_position, 1.0, E.Type.ARCANE)
		do_teleport.rpc_id(peer_id, destination)
		for target in _damageables():
			if target.global_position.distance_to(destination) <= skill.radius and _is_enemy(target):
				_strike(target, skill.damage, charge)
		show_flash.rpc(destination, skill.radius, _look(charge, E.Type.ARCANE))
		return true
	return false


# Golpe giratório: todos ao redor levam dano, a carga e um empurrão.
func _whirl(skill: Dictionary, charge: Array) -> void:
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() > skill.radius:
			continue
		_strike(target, skill.damage, charge)
		if offset.length() > 0.01:
			_push(target, offset.normalized() * skill.push)
	show_flash.rpc(global_position, skill.radius, _look(charge, E.Type.EARTH))


# Investida: corre para a frente; quem estiver no caminho leva dano, a carga e um empurrão.
func _dash(skill: Dictionary, charge: Array) -> void:
	dash_direction = _forward()
	dash_hit_time = DASH_TIME + 0.1   # folga para a posição sincronizada alcançar
	dash_hit = []
	dash_elements = charge
	dash_damage = skill.damage
	dash_push = skill.push
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
		_strike(target, dash_damage, dash_elements)
		var away: Vector3 = target.global_position - global_position
		away.y = 0.0
		_push(target, (dash_direction + away.normalized() * 0.5).normalized() * dash_push)


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
	invisible = maxf(invisible - delta, 0.0)
	_update_mana(delta)
	_update_bubble(delta)
	_update_dash_hits(delta)
	_update_cooldowns(delta)
	_update_storm(delta)
	if _is_channeling():
		if health.is_disabled():
			_stop_channel()
		else:
			_update_channel(delta)


func _update_mana(delta: float) -> void:
	if health.dead or mana >= max_mana:
		return
	var regen: float = cls.mana_regen
	if moba and is_at_shop():
		regen *= FOUNTAIN_MANA_MULT
	mana = minf(mana + regen * delta, max_mana)


func _update_cooldowns(delta: float) -> void:
	if skill_cooldowns.is_empty():
		return
	var cooldowns := {}
	for slot in skill_cooldowns:
		var left: float = skill_cooldowns[slot] - delta
		if left > 0.0:
			cooldowns[slot] = left
	skill_cooldowns = cooldowns


# Raio laser: dano por segundo no primeiro alvo da linha, com a carga.
func _update_channel(delta: float) -> void:
	channel_time += delta
	if channel_time >= channel_limit:
		_stop_channel()
		return
	var origin := global_position + Vector3.UP
	var result := _raycast(origin, origin + _forward() * channel_range)
	var length := channel_range
	if not result.is_empty():
		length = origin.distance_to(result.position)
		_strike(result.collider, channel_dps, channel_elements, delta)
	fx_length = length
	fx_width = 0.3


func _stop_channel() -> void:
	_cancel_channel()


func _cancel_channel() -> void:
	channel_shape = SpellResolver.Shape.NONE
	channel_elements = []
	fx_shape = SpellResolver.Shape.NONE
	fx_elements = []
	_cast_dir = Vector3.ZERO


func _fire_projectile(charge: Array, damage: float, speed: float, style: String, backstab: float, splash := 0.0) -> void:
	get_parent().spawn_entity({
		"type": "projectile",
		"pos": global_position + Vector3.UP,
		"dir": _forward(),
		"elements": charge,
		"caster": String(name),
		"team": team,
		"power": cls.spell_power * _might(),
		"speed": speed,
		"damage": damage,
		"style": style,
		"backstab": backstab,
		"splash": splash,
	})


# --- Ultimates (host) --------------------------------------------------------
# Voláteis (ultimates.gd): 3 elementos iguais = versão MEGA; senão, o elemento
# dominante decide qual sai, os outros vão junto como reforço e cada um deixa a
# sua zona no local. `scale`: força do ultimate na classe.

func _cast_ultimate(id: String, charge: Array, point: Vector3, scale: float) -> bool:
	var extra := charge.filter(func(element): return element != Ultimates.dominant(charge))
	var zones := Ultimates.zone_elements(charge)
	var strength := scale * _might()
	var center := global_position
	match id:
		"meteor":
			center = _clamp_target(point, METEOR_RANGE)
			_spawn_meteor(center, strength, extra, zones)
			zones = []   # o meteoro deixa as zonas quando cai
		"storm":
			_start_storm(STORM_TIME, STORM_INTERVAL, 0, [E.Type.LIGHTNING, E.Type.LIGHTNING] + extra, strength)
		"frost":
			for enemy in _hostile_units(FROST_RADIUS):
				enemy.health.freeze(FROST_TIME)
				_hit(enemy, extra, scale)
			show_flash.rpc(global_position, FROST_RADIUS, E.Type.COLD)
		"blessing":
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) != team:
					continue
				player.health.revive()
				player.health.apply_elements([E.Type.LIFE, E.Type.LIFE], strength)
				if not extra.is_empty():
					player.health.set_ward(extra)
				show_flash.rpc(player.global_position, 1.5, E.Type.LIFE)
		"quake":
			for enemy in _hostile_units(QUAKE_RADIUS):
				_strike(enemy, QUAKE_DAMAGE, extra, scale)
				enemy.health.stun(QUAKE_STUN)
			show_flash.rpc(global_position, QUAKE_RADIUS, E.Type.EARTH)
		"cataclysm":
			var at := _clamp_target(point, CATACLYSM_RANGE)
			center = at
			show_flash.rpc(at, CATACLYSM_RADIUS * 0.5, E.Type.ARCANE)
			get_tree().create_timer(CATACLYSM_DELAY).timeout.connect(_cataclysm.bind(at, extra, scale))
		"tide":
			_wave(TIDE_RANGE, TIDE_ANGLE, 0.0, TIDE_PUSH, [E.Type.WATER, E.Type.WATER] + extra, scale, 3)
		"fortress":
			for i in 8:
				var angle := TAU * i / 8.0
				_spawn_barrier(global_position + Vector3(cos(angle), 0.0, sin(angle)) * 3.0, [E.Type.SHIELD] + extra)
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) == team and not player.health.dead \
						and player.global_position.distance_to(global_position) <= FORTRESS_RADIUS:
					player.health.shielded = maxf(player.health.shielded, FORTRESS_SHIELD)
		"eclipse":
			for enemy in _hostile_units(ECLIPSE_RADIUS):
				_strike(enemy, ECLIPSE_DAMAGE, [E.Type.VOID, E.Type.VOID] + extra, scale)
			show_flash.rpc(global_position, ECLIPSE_RADIUS, E.Type.VOID)
		"singularity":
			center = _clamp_target(point, SINGULARITY_RANGE)
			_singularity(center, extra, scale)
		"smokescreen":
			for enemy in _hostile_units(SMOKESCREEN_RADIUS):
				_hit(enemy, [E.Type.SMOKE] + extra, scale)
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) == team and not player.health.dead 						and player.global_position.distance_to(global_position) <= SMOKESCREEN_RADIUS:
					player.invisible = maxf(player.invisible, SMOKESCREEN_HIDE)
			show_flash.rpc(global_position, SMOKESCREEN_RADIUS, E.Type.SMOKE)
		"blood_moon":
			_blood_burst(BLOOD_MOON_RADIUS, BLOOD_MOON_DAMAGE, Health.BLEED_TIME, 0.5, extra, scale)
		_:
			if not _cast_mega(id, point, scale, strength):
				return false
	if not zones.is_empty():
		_spawn_zone(center, zones, ZONE_RADIUS, ZONE_TIME, strength)
	return true


# Versões MEGA (3 elementos iguais).
func _cast_mega(id: String, point: Vector3, scale: float, strength: float) -> bool:
	match id:
		"mega_fire":
			# Chuva de meteoros: um no cursor e os outros espalhados em volta, um depois do outro.
			var at := _clamp_target(point, METEOR_RANGE)
			for i in RAIN_METEORS:
				var spot := at
				if i > 0:
					var angle := TAU * i / float(RAIN_METEORS - 1) + randf_range(-0.4, 0.4)
					spot = _clamp_target(at + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.5, RAIN_SPREAD),
						METEOR_RANGE + RAIN_SPREAD)
				get_tree().create_timer(RAIN_DELAY * i).timeout.connect(_spawn_meteor.bind(spot, strength * 0.8, [], []))
		"mega_lightning":
			_start_storm(MEGA_STORM_TIME, MEGA_STORM_INTERVAL, MEGA_STORM_CHAIN,
				[E.Type.LIGHTNING, E.Type.LIGHTNING, E.Type.LIGHTNING], strength)
		"mega_cold":
			for enemy in _hostile_units(ICE_AGE_RADIUS):
				enemy.health.freeze(ICE_AGE_FREEZE)
				_hit(enemy, [E.Type.COLD], scale)
			_spawn_zone(global_position, [E.Type.COLD, E.Type.COLD, E.Type.COLD], ICE_AGE_RADIUS * 0.7, ICE_AGE_FREEZE + 1.0, strength)
			show_flash.rpc(global_position, ICE_AGE_RADIUS, E.Type.COLD)
		"mega_life":
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) != team:
					continue
				player.health.revive()
				player.health.heal(player.health.max_hp)
				player.health.haste(0.3, 4.0)
				show_flash.rpc(player.global_position, 2.0, E.Type.LIFE)
		"mega_earth":
			_fissure(scale)
		"mega_arcane":
			show_flash.rpc(global_position, SUPERNOVA_RADIUS * 0.3, E.Type.ARCANE)
			get_tree().create_timer(SUPERNOVA_DELAY).timeout.connect(_supernova.bind(scale))
		"mega_water":
			_wave(TSUNAMI_RANGE, TSUNAMI_ANGLE, TSUNAMI_DAMAGE, MAX_PUSH,
				[E.Type.WATER, E.Type.WATER, E.Type.WATER], scale, 5)
		"mega_shield":
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) == team and not player.health.dead \
						and player.global_position.distance_to(global_position) <= BASTION_RADIUS:
					player.health.add_barrier(Health.INVULNERABLE_BARRIER, BASTION_TIME)
					player.health.shielded = maxf(player.health.shielded, BASTION_TIME)
			show_flash.rpc(global_position, BASTION_RADIUS, E.Type.SHIELD)
		"mega_void":
			for enemy in _hostile_units(BLACKOUT_RADIUS):
				_strike(enemy, ECLIPSE_DAMAGE, [E.Type.VOID], scale)
				enemy.health.silence(BLACKOUT_TIME)
				if enemy.get("mana") != null:
					enemy.mana = 0.0
			show_flash.rpc(global_position, BLACKOUT_RADIUS, E.Type.VOID)
		"mega_gravity":
			var at := _clamp_target(point, SINGULARITY_RANGE)
			_spawn_zone(at, [E.Type.GRAVITY, E.Type.GRAVITY, E.Type.GRAVITY], BLACK_HOLE_RADIUS, BLACK_HOLE_TIME,
				strength, BLACK_HOLE_DPS)
			show_flash.rpc(at, BLACK_HOLE_RADIUS, E.Type.GRAVITY)
		"mega_smoke":
			# Mega fumaça: cega os inimigos e apaga a visão deles (tela escura); o time some na nuvem.
			for enemy in _hostile_units(MEGA_SMOKE_RADIUS):
				_hit(enemy, [E.Type.SMOKE], scale)
				enemy.health.blinded = maxf(enemy.health.blinded, BLACKOUT_TIME)
				enemy.health.blackout = maxf(enemy.health.blackout, BLACKOUT_TIME)
			_spawn_zone(global_position, [E.Type.SMOKE, E.Type.SMOKE, E.Type.SMOKE], MEGA_SMOKE_RADIUS, BLACKOUT_TIME, strength)
			show_flash.rpc(global_position, MEGA_SMOKE_RADIUS, E.Type.SMOKE)
		"mega_blood":
			_blood_burst(FEAST_RADIUS, FEAST_DAMAGE, FEAST_BLEED, 1.0, [], scale)
			for player in get_tree().get_nodes_in_group("players"):
				if Combat.team_of(player) == team and not player.health.dead \
						and player.global_position.distance_to(global_position) <= FEAST_RADIUS:
					player.health.lifesteal_buff(FEAST_TEAM_STEAL, LIFESTEAL_TIME)
		_:
			return false
	return true


func _spawn_meteor(at: Vector3, strength: float, extra: Array, zones: Array) -> void:
	if not is_inside_tree():
		return
	get_parent().spawn_entity({"type": "meteor", "team": team, "pos": at, "extra": extra,
		"strength": strength, "caster": String(name), "zone_elements": zones})


func _spawn_zone(at: Vector3, zone_elements: Array, radius: float, duration: float, strength: float, dps := 0.0) -> void:
	get_parent().spawn_entity({"type": "zone", "pos": Vector3(at.x, 0.0, at.z), "team": team,
		"caster": String(name), "elements": zone_elements, "strength": strength,
		"radius": radius, "duration": duration, "dps": dps})


func _start_storm(duration: float, interval: float, chain: int, bolt_elements: Array, strength: float) -> void:
	storm_time = duration
	storm_tick = 0.0
	storm_interval = interval
	storm_chain = chain
	storm_elements = bolt_elements
	storm_scale = strength


# Lua de sangue / Banquete: inimigos perto levam dano e sangram; quem lançou
# cura `steal` do dano causado (além do roubo de vida normal).
func _blood_burst(radius: float, damage: float, bleed_time: float, steal: float, extra: Array, scale: float) -> void:
	var dealt := 0.0
	for enemy in _hostile_units(radius):
		dealt += _strike(enemy, damage, extra, scale)
		enemy.health.bleed(bleed_time)
	health.heal(dealt * steal)
	show_flash.rpc(global_position, radius, E.Type.BLOOD)


# Onda à frente (Maremoto/Tsunami): molha, causa dano e empurra.
func _wave(reach: float, angle: float, damage: float, push_force: float, wave_elements: Array, scale: float, steps: int) -> void:
	for target in _damageables():
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		if offset.length() < 0.01 or offset.length() > reach or _forward().angle_to(offset.normalized()) > angle:
			continue
		_strike(target, damage, wave_elements, scale)
		_push(target, offset.normalized() * push_force)
	for step in steps:
		show_flash.rpc(global_position + _forward() * (2.0 + reach / steps * step), 2.0 + step, E.Type.WATER)


# Fenda: rachadura em linha à frente que fere e atordoa, com paredes de pedra dos lados.
func _fissure(scale: float) -> void:
	var direction := _forward()
	for enemy in _hostile_units(FISSURE_LENGTH + 1.0):
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var along := offset.dot(direction)
		if along < 0.0 or along > FISSURE_LENGTH or (offset - direction * along).length() > FISSURE_WIDTH:
			continue
		_strike(enemy, FISSURE_DAMAGE, [], scale)
		enemy.health.stun(FISSURE_STUN)
	var side := direction.cross(Vector3.UP).normalized()
	var yaw := atan2(direction.x, direction.z) + PI / 2.0
	for i in 4:
		var at := global_position + direction * (2.0 + 4.0 * i)
		show_flash.rpc(at, FISSURE_WIDTH, E.Type.EARTH)
		if i > 0:
			_spawn_barrier(at + side * (FISSURE_WIDTH + 1.0), [E.Type.SHIELD, E.Type.EARTH], yaw)
			_spawn_barrier(at - side * (FISSURE_WIDTH + 1.0), [E.Type.SHIELD, E.Type.EARTH], yaw)


# Supernova (depois da carga): explosão enorme em volta de quem lançou.
func _supernova(scale: float) -> void:
	if not is_inside_tree() or health.dead:
		return
	for enemy in _hostile_units(SUPERNOVA_RADIUS):
		_strike(enemy, SUPERNOVA_DAMAGE, [], scale)
		var away: Vector3 = enemy.global_position - global_position
		away.y = 0.0
		if away.length() > 0.01:
			_push(enemy, away.normalized() * MAX_PUSH)
	show_flash.rpc(global_position, SUPERNOVA_RADIUS, E.Type.ARCANE)


# Singularidade: suga os inimigos perto de `at` para o centro, causa dano e atordoa.
func _singularity(at: Vector3, extra: Array, scale: float) -> void:
	for target in _damageables():
		if not _is_enemy(target) or target.is_in_group("structures") or target.health.dead:
			continue
		var offset: Vector3 = at - target.global_position
		offset.y = 0.0
		if offset.length() > SINGULARITY_RADIUS:
			continue
		_strike(target, SINGULARITY_DAMAGE, extra, scale)
		target.health.stun(SINGULARITY_STUN)
		if offset.length() > 0.5:
			_push(target, offset.normalized() * minf(offset.length() * 2.5, MAX_PUSH))
	show_flash.rpc(at, SINGULARITY_RADIUS, E.Type.GRAVITY)


# Explosão do Cataclismo (depois do atraso). O personagem pode ter caído ou saído.
func _cataclysm(at: Vector3, extra: Array, scale: float) -> void:
	if not is_inside_tree():
		return
	for target in _damageables():
		var offset: Vector3 = target.global_position - at
		offset.y = 0.0
		if offset.length() <= CATACLYSM_RADIUS:
			_strike(target, CATACLYSM_DAMAGE, extra, scale)
			if offset.length() > 0.01:
				_push(target, offset.normalized() * 8.0)
	show_flash.rpc(at, CATACLYSM_RADIUS, E.Type.ARCANE)


func _update_storm(delta: float) -> void:
	if storm_time <= 0.0:
		return
	storm_time -= delta
	storm_tick -= delta
	if storm_tick > 0.0:
		return
	storm_tick = storm_interval
	var targets := _hostile_units(STORM_RANGE)
	if targets.is_empty():
		return
	var target: Node3D = targets.pick_random()
	drain(target.health.apply_elements(storm_elements, storm_scale), storm_elements)
	show_bolt.rpc(target.global_position)
	# Tempestade suprema: o raio salta para os inimigos mais perto do primeiro.
	if storm_chain > 0:
		targets.erase(target)
		targets.sort_custom(func(a, b): return a.global_position.distance_to(target.global_position) \
			< b.global_position.distance_to(target.global_position))
		for other in targets.slice(0, storm_chain):
			drain(other.health.apply_elements(storm_elements, storm_scale * 0.6), storm_elements)
			show_bolt.rpc(other.global_position)


# Ponto no chão a no máximo `max_range` do personagem, dentro do mapa.
func _clamp_target(point: Vector3, max_range: float) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() > max_range:
		offset = offset.normalized() * max_range
	var target := global_position + offset
	var half: Vector2 = get_parent().get("map_half") if get_parent().get("map_half") != null else Vector2(18.5, 18.5)
	half -= Vector2(1.5, 1.5)
	return Vector3(clampf(target.x, -half.x, half.x), 0.0, clampf(target.z, -half.y, half.y))


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
	flash.material_override = Vfx.glow_material(Color(color, 1.0), 1.5, 0.35)
	get_parent().add_child(flash)
	flash.global_position = Vector3(at.x, 0.05, at.z)
	get_tree().create_timer(0.3).timeout.connect(flash.queue_free)
	Audio.play("heal" if element == E.Type.LIFE else "area", at, minf(radius - 3.0, 3.0))
	# Anel de partículas abrindo do centro.
	Vfx.burst(get_parent(), Vector3(at.x, 0.4, at.z), element, int(clampf(radius * 14.0, 16.0, 90.0)), radius * 0.3, radius * 2.2)


@rpc("any_peer", "call_local", "reliable")
func show_swing(element: int, direction: Vector3, weapon_range: float) -> void:
	if _sender() != 1:
		return
	var swing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(weapon_range * 1.2, 0.15, 0.4)
	swing.mesh = box
	var color: Color = E.COLORS[element] if element >= 0 else Color(0.9, 0.9, 0.95)
	swing.material_override = Vfx.glow_material(color, 2.0, 0.75)
	get_parent().add_child(swing)
	var center := global_position + direction.normalized() * (weapon_range * 0.6)
	swing.global_position = Vector3(center.x, 1.0, center.z)
	swing.look_at(swing.global_position + direction, Vector3.UP)
	swing.rotate_object_local(Vector3.UP, PI / 2.0)
	get_tree().create_timer(0.12).timeout.connect(swing.queue_free)
	Audio.play("chop" if class_id == "fighter" else "slash", swing.global_position)
	Audio.play("whoosh", swing.global_position, -4.0)
	if element >= 0:
		Vfx.burst(get_parent(), swing.global_position, element, 14, 0.5, 2.5)


@rpc("any_peer", "call_local", "reliable")
func show_bolt(at: Vector3) -> void:
	if _sender() != 1:
		return
	# Raio em zigue-zague caindo do céu, com faíscas no chão.
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 13:
		var jitter := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)) if i > 0 and i < 12 else Vector3.ZERO
		lines.surface_add_vertex(Vector3(0, 12.0 - i, 0) + jitter)
	lines.surface_end()
	var bolt := MeshInstance3D.new()
	bolt.mesh = lines
	bolt.material_override = Vfx.glow_material(E.COLORS[E.Type.LIGHTNING], 5.0)
	get_parent().add_child(bolt)
	bolt.global_position = Vector3(at.x, 0.0, at.z)
	get_tree().create_timer(0.15).timeout.connect(bolt.queue_free)
	Audio.play("bolt", bolt.global_position)
	Vfx.burst(get_parent(), Vector3(at.x, 0.3, at.z), E.Type.LIGHTNING, 24, 0.3, 4.0)


# --- Utilidades (host) -------------------------------------------------------

# Tudo que tem vida, menos o próprio personagem. Quem pode ser atingido
# depende do modo (ver combat.gd): na Arena há fogo amigo; no MOBA, não.
func _damageables() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("damageable"):
		if node != self and node is Node3D and not node.is_queued_for_deletion():
			result.append(node)
	return result


# Unidades hostis vivas (sem estruturas) num raio, para os ultimates.
func _hostile_units(radius: float) -> Array:
	return _damageables().filter(func(node): return Combat.is_hostile(team, Combat.team_of(node)) \
		and not node.is_in_group("structures") and not node.health.dead \
		and node.global_position.distance_to(global_position) <= radius)


# Elementos da carga num alvo: a força depende da classe (aliados só recebem Vida).
func _hit(target: Node, elements: Array, scale: float) -> float:
	var target_health := target.get_node_or_null("Health")
	if target_health == null:
		return 0.0
	var dealt := 0.0
	elements = Combat.filter_elements(team, target, elements)
	if not elements.is_empty():
		dealt = target_health.apply_elements(elements, scale * cls.spell_power * _might())
	# Gravidade puxa o alvo para quem lançou (no laser, por segundo).
	var gravity := elements.count(E.Type.GRAVITY)
	if gravity > 0 and target != self and target is Node3D:
		var toward: Vector3 = global_position - target.global_position
		toward.y = 0.0
		if toward.length() > 1.2:
			_push(target, toward.normalized() * GRAVITY_PULL * gravity * minf(scale, 1.0))
	return dealt


# Força de dano: nível/itens/bônus, pela metade se o personagem estiver cego (Fumaça).
func _might() -> float:
	return power * (BLIND_FACTOR if health.blinded > 0.0 else 1.0)


func _push(target: Node, impulse: Vector3) -> void:
	if target.has_method("push") and Combat.can_harm(team, target):
		target.push(impulse)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_barrier(at: Vector3, elements: Array, yaw := NAN) -> void:
	_act("Spellcast_Raise")
	var offset := at - global_position
	get_parent().spawn_entity({
		"type": "barrier",
		"pos": Vector3(at.x, 0.0, at.z),
		"yaw": atan2(offset.x, offset.z) if is_nan(yaw) else yaw,
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
	max_mana = stats.max_mana
	mana = minf(mana, max_mana)
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
	mana = max_mana
	var spot := MobaMap.spawn_point(team, color_index)
	do_teleport.rpc_id(peer_id, spot)


func _on_died() -> void:
	if moba:
		respawn_time = Progression.respawn_time(level)
	_cancel_channel()
	_clear_queue()
	storm_time = 0.0
	invisible = 0.0
	dash_hit_time = 0.0
	bubble_time = 0.0
	bubble_elements = []
