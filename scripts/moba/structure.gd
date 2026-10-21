# Estrutura do MOBA: torre, inibidor ou nexus.
# - Torre: atira no inimigo mais próximo dentro do alcance (tropas primeiro).
# - Inibidor: se cair, o time inimigo ganha supertropas nessa rota (e ele volta depois).
# - Nexus: se cair, o time perde.
# Fica invulnerável até cair alguma das estruturas em "requires" (o MobaState controla).
# Em rede: o host decide tiros e dano; vida/estado são sincronizados.
extends StaticBody3D

const E = preload("res://scripts/core/elements.gd")
const Health = preload("res://scripts/core/health.gd")
const Combat = preload("res://scripts/core/combat.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const HealthBar = preload("res://scripts/vfx/health_bar.gd")
const UnitSounds = preload("res://scripts/audio/unit_sounds.gd")

const MEDIEVAL := "res://assets/models/kaykit/medieval/"
# Modelo e escala por estrutura (KayKit Medieval Hexagon, CC0). O inibidor é um cristal.
const LOOKS := {
	"tower": ["building_tower_A_%s.gltf", 2.1],
	"nexus_tower": ["building_tower_B_%s.gltf", 2.0],
	"nexus": ["building_castle_%s.gltf", 1.5],
}

const KINDS := {
	"tower": {"label": "Torre", "hp": 2200.0, "radius": 1.2, "height": 4.5},
	"inhibitor": {"label": "Inibidor", "hp": 1600.0, "radius": 1.4, "height": 2.0},
	"nexus": {"label": "Nexus", "hp": 3200.0, "radius": 2.6, "height": 3.0},
}
const TOWER_RANGE := 10.0
const TOWER_COOLDOWN := 1.0
const TOWER_DAMAGE_CHAMPION := 90.0
const TOWER_DAMAGE_MINION_FRACTION := 0.4   # da vida máxima da tropa

var kind := "tower"
var team := Combat.BLUE
var struct_id := ""
var lane := ""
var info: Dictionary
var health: Health
var label: Label3D
var body_mesh: MeshInstance3D
var collision: CollisionShape3D
var target: Node3D
var model: Node3D
var ruin: Node3D
var shot_timer := 0.0
var _shown_dead := false


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("structures")
	info = KINDS[kind]
	var radius: float = info.radius
	var height: float = info.height

	collision = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height / 2.0
	add_child(collision)

	body_mesh = MeshInstance3D.new()
	if kind == "tower" or kind == "nexus":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius * 0.7
		cylinder.bottom_radius = radius
		cylinder.height = height
		body_mesh.mesh = cylinder
	elif kind == "inhibitor":
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = radius
		crystal.height = height
		body_mesh.mesh = crystal
	else:
		var core := SphereMesh.new()
		core.radius = radius
		core.height = height
		body_mesh.mesh = core
	body_mesh.position.y = height / 2.0
	var color: Color = Combat.TEAM_COLORS[team]
	body_mesh.material_override = E.make_material(color.darkened(0.2))
	add_child(body_mesh)

	var look_id := "nexus_tower" if struct_id.ends_with("torre_nexus") else kind
	if LOOKS.has(look_id):
		body_mesh.visible = false
		var look: Array = LOOKS[look_id]
		var color_key := "blue" if team == Combat.BLUE else "red"
		model = load(MEDIEVAL + (look[0] % color_key)).instantiate()
		model.scale = Vector3.ONE * look[1]
		add_child(model)
		ruin = load(MEDIEVAL + "building_destroyed.gltf").instantiate()
		ruin.scale = Vector3.ONE * look[1] * 0.9
		ruin.visible = false
		add_child(ruin)
	else:
		# Inibidor: cristal brilhante girando, com partículas.
		body_mesh.material_override = Vfx.glow_material(color, 2.0, 0.9)
		var sparks := Vfx.emitter(E.Type.ARCANE if team == Combat.RED else E.Type.LIGHTNING,
			{"amount": 20, "lifetime": 1.0, "speed": 1.0, "sphere": radius, "size_scale": 1.2})
		sparks.position.y = height / 2.0
		sparks.emitting = true
		add_child(sparks)
	Vfx.add_ring(self, color, radius + 0.8)

	health = Health.new()
	health.name = "Health"
	health.max_hp = info.hp
	health.immune_status = true
	add_child(health)

	var bar := HealthBar.new()
	bar.width = 2.6
	bar.height_above = height + 1.4
	add_child(bar)
	var sounds := UnitSounds.new()
	sounds.material = "stone"
	add_child(sounds)

	label = Label3D.new()
	label.position.y = height + 2.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.modulate = color.lightened(0.4)
	add_child(label)

	SyncUtil.add_sync(self, "StateSync", 1, ["Health:hp", "Health:dead", "Health:invulnerable"])


func is_destroyed() -> bool:
	return health.dead


func _process(_delta: float) -> void:
	var text: String = info.label
	if health.dead:
		text = "%s destruído" % info.label
	elif health.invulnerable:
		text += "\n(protegido)"
	label.text = text
	if health.dead != _shown_dead:
		_shown_dead = health.dead
		_update_destroyed_visual()


# Destruída: vira escombro baixo e dá para passar por cima.
func _update_destroyed_visual() -> void:
	collision.disabled = health.dead
	if model != null:
		model.visible = not health.dead
		ruin.visible = health.dead
	else:
		body_mesh.scale = Vector3(1.0, 0.15, 1.0) if health.dead else Vector3.ONE
		body_mesh.transparency = 0.4 if health.dead else 0.0
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = not health.dead
	if health.dead:
		Vfx.burst(get_parent(), global_position + Vector3.UP * 2.0, E.Type.EARTH, 80, 1.5, 6.0)
		Vfx.burst(get_parent(), global_position + Vector3.UP * 2.0, E.Type.STEAM, 40, 1.5, 3.0)


# Volta inteira (inibidor renascendo).
func rebuild() -> void:
	health.reset()


func _physics_process(delta: float) -> void:
	if kind != "tower" or not multiplayer.is_server() or health.dead:
		return
	shot_timer -= delta
	if not _is_valid_target(target):
		target = _pick_target()
	if target != null and shot_timer <= 0.0:
		shot_timer = TOWER_COOLDOWN
		_shoot(target)


func _shoot(victim: Node3D) -> void:
	var damage := TOWER_DAMAGE_CHAMPION
	if victim.is_in_group("minions"):
		damage = victim.health.max_hp * TOWER_DAMAGE_MINION_FRACTION
	victim.health.damage(damage)
	show_shot.rpc(victim.global_position)


# Tropas primeiro; campeões só sem tropas inimigas por perto.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("damageable"):
		if not _is_valid_target(node):
			continue
		var distance := global_position.distance_to(node.global_position)
		var score := distance + (0.0 if node.is_in_group("minions") else 1000.0)
		if score < best_score:
			best_score = score
			best = node
	return best


func _is_valid_target(node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node == self:
		return false
	if node.is_in_group("structures") or not Combat.is_hostile(team, Combat.team_of(node)):
		return false
	if Combat.team_of(node) == Combat.NEUTRAL:
		return false   # torres ignoram os monstros da selva
	if node.health.dead or node.get("invisible") != null and node.invisible > 0.0:
		return false
	var offset: Vector3 = node.global_position - global_position
	offset.y = 0.0
	return offset.length() <= TOWER_RANGE


@rpc("any_peer", "call_local", "reliable")
func show_shot(at: Vector3) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	var from: Vector3 = global_position + Vector3.UP * (info.height + 0.3)
	var to := at + Vector3.UP
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.15, from.distance_to(to))
	beam.mesh = box
	beam.material_override = Vfx.glow_material(Combat.TEAM_COLORS[team].lightened(0.4), 4.0)
	get_parent().add_child(beam)
	beam.global_position = (from + to) / 2.0
	beam.look_at(to, Vector3.UP)
	get_tree().create_timer(0.12).timeout.connect(beam.queue_free)
	Vfx.burst(get_parent(), to, E.Type.LIGHTNING if team == Combat.BLUE else E.Type.FIRE, 16, 0.2, 3.0)
	Audio.play("tower_shot", from)
