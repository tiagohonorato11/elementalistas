# Zona elemental no chão (Mini meteoro do Mago e elementos secundários do ultimate).
# Dura `duration` s; cada elemento tem um efeito próprio, mais forte quando repete
# (2 iguais: 1,5x; 3 iguais: 2x). Inimigos sofrem os efeitos; aliados recebem os bons.
#   Fogo: queima (dano por segundo)          Gravidade: puxa para o centro
#   Frio: lento; quem fica 2,5 s congela     Gelo: estilhaços ao cair (dano + empurra)
#   Raio: um raio a cada 0,5 s num inimigo   Água: molha e empurra para fora ao cair
#   Vapor: escalda (dano/s) e deixa lento    Terra: impacto forte e atordoa 0,75 s
#   Arcano: explode de novo depois de 1,5 s  Vida: cura os aliados
#   Escudo: aliados levam metade do dano     Vazio: desfaz proteções e drena mana
#   Fumaça: cega inimigos, esconde aliados   Sangue: inimigos sangram (quem lançou rouba vida)
# Em rede: todos mostram a zona; só o host aplica os efeitos e a remove.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")
const Health = preload("res://scripts/core/health.gd")

const TICK := 0.5
const FIRE_DPS := 12.0
const STEAM_DPS := 10.0
const BLOOD_DPS := 4.0
const LIFE_HPS := 10.0
const VOID_MANA_PER_SECOND := 10.0
const COLD_FREEZE_AFTER := 2.5
const COLD_FREEZE_TIME := 2.0
const ICE_DAMAGE := 30.0
const EARTH_DAMAGE := 40.0
const EARTH_STUN := 0.75
const ARCANE_DELAY := 1.5
const ARCANE_DAMAGE := 50.0
const BOLT_SCALE := 0.66      # Raio: 30 x 0,66 = 20 de dano (o dobro em quem está molhado)
const PULL := 6.0
const PUSH_OUT := 8.0

var team := Combat.NEUTRAL
var caster_name := ""
var elements: Array = []
var strength := 1.0
var radius := 3.5
var duration := 3.0
var dps := 0.0                 # dano extra por segundo (Buraco negro)
var age := 0.0
var _tick := 0.0
var _arcane_done := false
var _cold_time := {}           # instance id -> segundos dentro da zona (Frio)
var _disc: MeshInstance3D
var _emitters: Array = []


func _ready() -> void:
	_disc = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.04
	_disc.mesh = cylinder
	_disc.position.y = 0.05
	_disc.material_override = Vfx.glow_material(Vfx.mix_color(elements), 1.0, 0.22)
	add_child(_disc)
	for element in _distinct():
		var particles := Vfx.emitter(element, {"amount": int(clampf(radius * 10.0, 20.0, 120.0)), "lifetime": 1.0,
			"speed": 0.8, "box": Vector3(radius * 0.7, 0.3, radius * 0.7), "size_scale": 1.4})
		particles.position.y = 0.4
		particles.emitting = true
		add_child(particles)
		_emitters.append(particles)
	Audio.play("area", self, minf(radius - 3.0, 3.0))
	if multiplayer.is_server():
		_impact()


func _distinct() -> Array:
	var result: Array = []
	for element in elements:
		if not (element in result):
			result.append(element)
	return result


# Força de um elemento: 0 se ausente, 1 / 1,5 / 2 com 1 / 2 / 3 cópias.
func _mult(element: int) -> float:
	var count := elements.count(element)
	return 0.0 if count == 0 else 1.0 + 0.5 * (count - 1)


func _physics_process(delta: float) -> void:
	age += delta
	var fade := clampf((duration - age) / 0.5, 0.0, 1.0)
	_disc.transparency = 1.0 - fade
	if E.Type.GRAVITY in elements:
		rotation.y += delta * 2.0
	if not multiplayer.is_server():
		return
	if age >= duration:
		queue_free()
		return
	if E.Type.ARCANE in elements and not _arcane_done and age >= ARCANE_DELAY:
		_arcane_done = true
		_arcane_blast()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_pulse()


# --- Efeitos (host) ------------------------------------------------------------

func _units_inside() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("damageable"):
		if node.is_queued_for_deletion() or node.is_in_group("structures") or node.health.dead:
			continue
		var offset: Vector3 = node.global_position - global_position
		offset.y = 0.0
		if offset.length() <= radius:
			result.append(node)
	return result


func _enemies() -> Array:
	return _units_inside().filter(func(node): return Combat.is_hostile(team, Combat.team_of(node)))


func _allies() -> Array:
	return _units_inside().filter(func(node): return Combat.team_of(node) == team)


func _away(node: Node3D) -> Vector3:
	var offset := node.global_position - global_position
	offset.y = 0.0
	return offset.normalized() if offset.length() > 0.01 else Vector3.ZERO


func _push(node: Node, impulse: Vector3) -> void:
	if node.has_method("push"):
		node.push(impulse)


# Dano direto em um inimigo; o dano volta como roubo de vida para quem lançou.
func _damage(node: Node, amount: float) -> void:
	_drain(node.health.damage(amount * strength))


func _drain(dealt: float) -> void:
	var caster := get_parent().get_node_or_null(caster_name)
	if caster != null and caster.has_method("drain"):
		caster.drain(dealt, elements)


# Na queda: Gelo, Água e Terra.
func _impact() -> void:
	for node in _enemies():
		if E.Type.ICE in elements:
			_damage(node, ICE_DAMAGE * _mult(E.Type.ICE))
			node.health.apply_elements([E.Type.ICE], 0.0)
			_push(node, _away(node) * 6.0)
		if E.Type.WATER in elements:
			node.health.apply_elements([E.Type.WATER], 0.0)
			_push(node, _away(node) * PUSH_OUT * _mult(E.Type.WATER))
		if E.Type.EARTH in elements:
			_damage(node, EARTH_DAMAGE * _mult(E.Type.EARTH))
			node.health.stun(EARTH_STUN * _mult(E.Type.EARTH))


func _arcane_blast() -> void:
	for node in _enemies():
		_damage(node, ARCANE_DAMAGE * _mult(E.Type.ARCANE))
		_push(node, _away(node) * 6.0)
	show_blast.rpc(E.Type.ARCANE)


func _pulse() -> void:
	var enemies := _enemies()
	for node in enemies:
		var health: Node = node.health
		var key: int = node.get_instance_id()
		if dps > 0.0:
			_damage(node, dps * TICK)
		if E.Type.FIRE in elements:
			_damage(node, FIRE_DPS * _mult(E.Type.FIRE) * TICK)
			if health.wet <= 0.0:
				health.burning = maxf(health.burning, 1.0)
		if E.Type.STEAM in elements:
			_damage(node, STEAM_DPS * _mult(E.Type.STEAM) * TICK)
			health.slow(0.25, TICK + 0.2)
		if E.Type.BLOOD in elements:
			_damage(node, BLOOD_DPS * _mult(E.Type.BLOOD) * TICK)
			health.bleed(1.5)
		if E.Type.COLD in elements:
			health.slow(minf(0.5 * _mult(E.Type.COLD), 0.8), TICK + 0.2)
			_cold_time[key] = _cold_time.get(key, 0.0) + TICK
			if _cold_time[key] >= COLD_FREEZE_AFTER and _cold_time[key] < COLD_FREEZE_AFTER + TICK:
				health.freeze(COLD_FREEZE_TIME)
		if E.Type.ICE in elements:
			health.slow(0.3, TICK + 0.2)
		if E.Type.WATER in elements:
			health.apply_elements([E.Type.WATER], 0.0)
		if E.Type.GRAVITY in elements:
			var toward: Vector3 = global_position - node.global_position
			toward.y = 0.0
			if toward.length() > 0.6:
				_push(node, toward.normalized() * minf(toward.length() * 2.5, PULL) * _mult(E.Type.GRAVITY))
		if E.Type.VOID in elements:
			health.dispel(VOID_MANA_PER_SECOND / Health.VOID_MANA_DRAIN * _mult(E.Type.VOID) * TICK)
		if E.Type.SMOKE in elements:
			health.blinded = maxf(health.blinded, TICK + 0.5)
	if E.Type.LIGHTNING in elements and not enemies.is_empty():
		var target: Node3D = enemies.pick_random()
		_drain(target.health.apply_elements([E.Type.LIGHTNING], BOLT_SCALE * _mult(E.Type.LIGHTNING) * strength))
		show_zap.rpc(target.global_position)
	for node in _allies():
		if E.Type.LIFE in elements:
			node.health.heal(LIFE_HPS * _mult(E.Type.LIFE) * TICK * strength)
		if E.Type.SHIELD in elements:
			node.health.fortify(0.5, TICK + 0.3)
		if E.Type.SMOKE in elements and node.get("invisible") != null:
			node.invisible = maxf(node.invisible, TICK + 0.3)


# --- Visual (todos os peers) -----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func show_zap(at: Vector3) -> void:
	Vfx.burst(get_parent(), Vector3(at.x, 0.8, at.z), E.Type.LIGHTNING, 24, 0.3, 4.0)
	Audio.play("bolt", at, -3.0)


@rpc("authority", "call_local", "reliable")
func show_blast(element: int) -> void:
	Vfx.burst(get_parent(), global_position + Vector3.UP * 0.5, element, int(radius * 25.0), radius * 0.3, radius * 2.2)
	Audio.play("explosion", global_position)
