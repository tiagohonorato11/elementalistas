# Projétil (Orbe do Mago, Adaga do Assassino, flecha do esqueleto): voa em linha
# reta, causa o dano base e aplica os elementos no primeiro alvo.
# O poder multiplica o dano, o tamanho e o empurrão. Adaga pelas costas: x backstab.
# Orbe volátil (splash > 0): cada elemento da carga deixa a orbe maior e ela explode
# em área no impacto (Fogo: área maior; Terra: empurra mais; Gravidade: puxa para
# o centro; Raio: salta para mais 2 inimigos). Sangue: quem lançou rouba vida.
# Em rede: todos movem o projétil localmente; só o host decide acertos e o remove.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const LIFETIME := 3.0
const BASE_PUSH := 2.0
const PUSH_PER_EARTH := 3.0
const PULL_PER_GRAVITY := 7.0   # Gravidade puxa o alvo de volta para quem lançou
const GROW_PER_ELEMENT := 0.3
const SPLASH_RADIUS := 1.5
const SPLASH_PER_ELEMENT := 0.75
const FIRE_SPLASH_BONUS := 1.0
const CHAIN_TARGETS := 2
const CHAIN_RANGE := 6.0

var elements: Array = []
var caster_name := ""
var team := Combat.NEUTRAL
var direction := Vector3.FORWARD
var power := 1.0
var speed := 18.0
var damage := 0.0              # dano direto, além dos elementos
var style := "orb"             # "orb" (esfera/pedra/cristal) ou "dagger"
var backstab := 1.0
var splash := 0.0              # fração do dano na explosão em área (0 = sem área)
var age := 0.0


func setup(p_elements: Array, p_caster_name: String, p_direction: Vector3,
		p_power := 1.0, p_speed := 18.0, p_team := Combat.NEUTRAL, p_damage := 0.0,
		p_style := "orb", p_backstab := 1.0, p_splash := 0.0) -> void:
	splash = p_splash
	damage = p_damage
	style = p_style
	backstab = p_backstab
	team = p_team
	elements = p_elements
	caster_name = p_caster_name
	direction = p_direction.normalized()
	power = p_power
	speed = p_speed


var _mesh: MeshInstance3D


func _volatile() -> bool:
	return splash > 0.0 and not elements.is_empty()


func splash_radius() -> float:
	return SPLASH_RADIUS + SPLASH_PER_ELEMENT * elements.size() \
		+ (FIRE_SPLASH_BONUS if E.Type.FIRE in elements else 0.0)


func _ready() -> void:
	add_to_group("projectiles")
	Audio.play("launch", self, (power - 1.0) * 3.0)
	# Adaga: lâmina fina. Gelo: cristal. Terra: pedra facetada. Outros: esfera brilhante.
	# Cada elemento deixa um rastro.
	_mesh = MeshInstance3D.new()
	var size := 0.15 + 0.12 * power
	if _volatile():
		size *= 1.0 + GROW_PER_ELEMENT * elements.size()
	var color: Color = Vfx.mix_color(elements) if not elements.is_empty() else E.COLORS[E.Type.ARCANE]
	if style == "dagger":
		var blade := BoxMesh.new()
		blade.size = Vector3(0.08, 0.04, 0.55)
		_mesh.mesh = blade
		_mesh.material_override = Vfx.glow_material(color.lerp(Color(0.85, 0.85, 0.9), 0.5), 1.2)
	elif E.Type.ICE in elements:
		var crystal := PrismMesh.new()
		crystal.size = Vector3(size * 1.2, size * 3.0, size * 1.2)
		_mesh.mesh = crystal
		_mesh.rotation.x = -PI / 2.0
		_mesh.material_override = Vfx.glow_material(E.COLORS[E.Type.ICE], 1.5)
	elif E.Type.EARTH in elements:
		var rock := SphereMesh.new()
		rock.radius = size
		rock.height = size * 1.8
		rock.radial_segments = 6
		rock.rings = 3
		_mesh.mesh = rock
		var material := StandardMaterial3D.new()
		material.albedo_color = E.COLORS[E.Type.EARTH]
		material.roughness = 1.0
		_mesh.material_override = material
	else:
		var orb := SphereMesh.new()
		orb.radius = size
		orb.height = size * 2.0
		_mesh.mesh = orb
		_mesh.material_override = Vfx.glow_material(color, 2.5)
	add_child(_mesh)
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)
	var trail_elements: Array = []
	for element in (elements if not elements.is_empty() else [E.Type.ARCANE]):
		if not (element in trail_elements):
			trail_elements.append(element)
	for element in trail_elements:
		var trail := Vfx.emitter(element, {"amount": 24, "lifetime": 0.35, "speed": 0.5, "spread": 180.0,
			"sphere": size * 0.6, "size_scale": 0.9 + 0.3 * power})
		trail.emitting = true
		add_child(trail)


func _process(delta: float) -> void:
	if style != "dagger":
		_mesh.rotate_object_local(Vector3.FORWARD, delta * 8.0)


# Impacto: explosão de partículas dos elementos (em todos os PCs, ao sumir).
func _exit_tree() -> void:
	var parent := get_parent()
	if parent == null or parent.is_queued_for_deletion():
		return
	var blast := splash_radius() if _volatile() else 1.0
	for element in (elements if not elements.is_empty() else [E.Type.ARCANE]).slice(0, 2):
		Vfx.burst(parent, global_position, element, int(16 * power * blast), 0.2 * blast, 3.5 * blast)
	var impact := "impact_ice" if E.Type.ICE in elements else "impact_rock" if E.Type.EARTH in elements else "impact_magic"
	Audio.play(impact, global_position, (power - 1.0) * 3.0)


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	if not multiplayer.is_server():
		global_position += step
		return

	age += delta
	if age > LIFETIME:
		queue_free()
		return
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + step)
	# Acerta mesmo começando dentro do alvo (inimigo colado no mago).
	query.hit_from_inside = true
	var caster := get_parent().get_node_or_null(caster_name) as CollisionObject3D
	if caster != null:
		query.exclude = [caster.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target: Object = hit.collider
		var target_health = target.get_node_or_null("Health")
		var hit_elements := Combat.filter_elements(team, target, elements)
		var bonus := backstab if backstab > 1.0 and _from_behind(target) else 1.0
		var dealt := 0.0
		if target_health != null and damage > 0.0 and Combat.can_harm(team, target):
			dealt += target_health.damage(damage * power * bonus)
		if target_health != null and not hit_elements.is_empty():
			dealt += target_health.apply_elements(hit_elements, power * bonus)
		if _volatile():
			dealt += _explode(hit.position, target)
		_drain(dealt)
		if target.has_method("push") and Combat.can_harm(team, target):
			var gravity := elements.count(E.Type.GRAVITY)
			if gravity > 0:
				target.push(-direction * PULL_PER_GRAVITY * gravity * power)
			else:
				var strength := (BASE_PUSH + PUSH_PER_EARTH * elements.count(E.Type.EARTH)) * power
				target.push(direction * strength)
		queue_free()
		return
	global_position = from + step


# Orbe volátil: explosão em área (sem o alvo direto). Devolve o dano causado.
func _explode(at: Vector3, direct: Object) -> float:
	var dealt := 0.0
	var reach := splash_radius()
	var earth := elements.count(E.Type.EARTH)
	var gravity := elements.count(E.Type.GRAVITY)
	var hit: Array = [direct]
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == direct or String(node.name) == caster_name or node.is_queued_for_deletion():
			continue
		var offset: Vector3 = node.global_position - at
		offset.y = 0.0
		if offset.length() > reach:
			continue
		dealt += _hit_node(node, damage * splash)
		hit.append(node)
		if node.has_method("push") and Combat.can_harm(team, node) and offset.length() > 0.01:
			if gravity > 0:
				node.push(-offset.normalized() * minf(offset.length() * 3.0, PULL_PER_GRAVITY) * gravity)
			else:
				node.push(offset.normalized() * (BASE_PUSH + PUSH_PER_EARTH * 2.0 * earth) * power)
	# Raio: salta para os inimigos mais perto que a explosão não pegou.
	if E.Type.LIGHTNING in elements:
		var others: Array = []
		for node in get_tree().get_nodes_in_group("damageable"):
			if node in hit or String(node.name) == caster_name or node.is_in_group("structures"):
				continue
			if Combat.is_hostile(team, Combat.team_of(node)) and not node.health.dead \
					and node.global_position.distance_to(at) <= CHAIN_RANGE:
				others.append(node)
		others.sort_custom(func(a, b): return a.global_position.distance_to(at) < b.global_position.distance_to(at))
		for node in others.slice(0, CHAIN_TARGETS):
			dealt += node.health.damage(damage * 0.5 * power)
			dealt += node.health.apply_elements([E.Type.LIGHTNING], power)
	return dealt


func _hit_node(node: Node, amount: float) -> float:
	var health = node.get_node_or_null("Health")
	if health == null:
		return 0.0
	var dealt := 0.0
	if Combat.can_harm(team, node):
		dealt += health.damage(amount * power)
	var hit_elements := Combat.filter_elements(team, node, elements)
	if not hit_elements.is_empty():
		dealt += health.apply_elements(hit_elements, power)
	return dealt


func _drain(dealt: float) -> void:
	var caster := get_parent().get_node_or_null(caster_name)
	if caster != null and caster.has_method("drain"):
		caster.drain(dealt, elements)


# Bolha do Mago com Arcano: o projétil volta contra quem lançou (host).
func reflect(new_team: int, new_caster: String) -> void:
	team = new_team
	caster_name = new_caster
	age = 0.0
	turn_back.rpc(-direction, global_position)


@rpc("authority", "call_local", "reliable")
func turn_back(new_direction: Vector3, at: Vector3) -> void:
	direction = new_direction.normalized()
	global_position = at
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)


# O alvo está de costas para o projétil (virado para o mesmo lado em que ele voa).
func _from_behind(target: Object) -> bool:
	if not (target is Node3D):
		return false
	var facing: Vector3 = -target.global_transform.basis.z
	facing.y = 0.0
	return facing.normalized().dot(direction) > 0.5
