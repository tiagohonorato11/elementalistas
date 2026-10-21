# Efeitos dos feitiços contínuos de um personagem (filho dele): spray, beam,
# arco elétrico e a carga do projétil. Lê fx_shape/fx_elements/fx_length, que o
# host sincroniza: funciona igual em todos os PCs.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const HAND_HEIGHT := 1.1
const SPRAY_LIFETIME := 0.45
const SPRAY_SPEED := 11.0      # ~5 m de alcance, como o spray de verdade
const ARC_REFRESH := 0.05
const SPRAY_SOUNDS := {
	E.Type.FIRE: "fire", E.Type.WATER: "water", E.Type.COLD: "cold", E.Type.STEAM: "steam",
}

var player: Node
var _spray := {}               # elemento -> emissor
var _beam: MeshInstance3D
var _beam_particles: GPUParticles3D
var _beam_element := -1
var _arc: MeshInstance3D
var _arc_mesh := ImmediateMesh.new()
var _arc_timer := 0.0
var _arc_material: StandardMaterial3D
var _charge: MeshInstance3D
var _charge_element := -1
# Sons contínuos: id -> player 3D (criados quando usados pela primeira vez).
var _loops := {}


func _ready() -> void:
	player = get_parent()

	_beam = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.14
	cylinder.bottom_radius = 0.14
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	_beam.mesh = cylinder
	_beam.rotation.x = PI / 2.0     # cilindro deitado ao longo de -Z
	_beam.visible = false
	add_child(_beam)

	_arc = MeshInstance3D.new()
	_arc.mesh = _arc_mesh
	_arc_material = Vfx.glow_material(E.COLORS[E.Type.LIGHTNING], 4.0)
	_arc.material_override = _arc_material
	_arc.visible = false
	add_child(_arc)

	_charge = MeshInstance3D.new()
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 4
	_charge.mesh = rock
	_charge.position = Vector3(0, HAND_HEIGHT, -0.9)
	_charge.visible = false
	add_child(_charge)


func _elements() -> Array:
	var elements: Array = player.fx_elements
	return elements if not elements.is_empty() else [player.fx_element]


func _process(delta: float) -> void:
	var shape: int = player.fx_shape
	_update_spray(shape == SpellResolver.Shape.SPRAY)
	_update_beam(shape == SpellResolver.Shape.BEAM)
	_update_arc(shape == SpellResolver.Shape.ARC, delta)
	_update_charge(shape == SpellResolver.Shape.PROJECTILE)
	_update_sound(shape)


# Um som contínuo por forma; no spray, um por elemento da mistura.
func _update_sound(shape: int) -> void:
	var wanted := {}
	if shape == SpellResolver.Shape.SPRAY:
		var elements := _elements()
		for element in elements:
			var id: String = SPRAY_SOUNDS.get(element, "")
			if not id.is_empty():
				wanted["spray_" + id] = true
	elif shape == SpellResolver.Shape.BEAM:
		wanted["beam_life" if E.Type.LIFE in _elements() else "beam_arcane"] = true
	elif shape == SpellResolver.Shape.ARC:
		wanted["arc"] = true
	elif shape == SpellResolver.Shape.PROJECTILE:
		wanted["charge"] = true
	for id in wanted:
		if not _loops.has(id):
			_loops[id] = Audio.make_loop(id, self)
	for id in _loops:
		var loop: Node = _loops[id]
		if loop == null:
			continue
		var on: bool = wanted.has(id)
		if loop.playing != on:
			loop.playing = on
		if id == "charge" and on:
			loop.pitch_scale = 0.8 + 0.8 * clampf(player.fx_length, 0.0, 1.0)



# Um jato de partículas por elemento diferente da combinação.
func _update_spray(active: bool) -> void:
	var wanted: Array = []
	if active:
		for element in _elements():
			if not (element in wanted):
				wanted.append(element)
	for element in wanted:
		if not _spray.has(element):
			var particles := Vfx.emitter(element, {
				"amount": 60, "lifetime": SPRAY_LIFETIME, "speed": SPRAY_SPEED, "spread": 22.0,
				"direction": Vector3(0, 0, -1), "size_scale": 1.4,
			})
			particles.position = Vector3(0, HAND_HEIGHT, -0.4)
			add_child(particles)
			_spray[element] = particles
	for element in _spray:
		var on: bool = element in wanted
		if _spray[element].emitting != on:
			_spray[element].emitting = on


func _update_beam(active: bool) -> void:
	_beam.visible = active
	if _beam_particles != null:
		_beam_particles.emitting = active
	if not active:
		return
	var elements := _elements()
	var element: int = elements[0]
	if element != _beam_element:
		_beam_element = element
		_beam.material_override = Vfx.glow_material(Vfx.mix_color(elements), 3.0, 0.85)
		if _beam_particles != null:
			_beam_particles.queue_free()
		_beam_particles = Vfx.emitter(element, {"amount": 40, "lifetime": 0.4, "speed": 0.6, "spread": 180.0, "box": Vector3.ONE})
		add_child(_beam_particles)
	var length := maxf(player.fx_length, 0.1)
	var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.03)
	_beam.scale = Vector3(pulse, length, pulse)
	_beam.position = Vector3(0, HAND_HEIGHT, -length / 2.0)
	_beam_particles.position = _beam.position
	(_beam_particles.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.15, 0.15, length / 2.0)


# Zigue-zague que muda o tempo todo, do personagem até o primeiro alvo.
func _update_arc(active: bool, delta: float) -> void:
	_arc.visible = active
	if not active:
		return
	_arc_timer -= delta
	if _arc_timer > 0.0:
		return
	_arc_timer = ARC_REFRESH
	var length := maxf(player.fx_length, 0.5)
	var segments := maxi(int(length / 0.6), 3)
	_arc_mesh.clear_surfaces()
	for strand in 2:
		_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in segments + 1:
			var t := float(i) / segments
			var jitter := Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0.0) if i > 0 and i < segments else Vector3.ZERO
			_arc_mesh.surface_add_vertex(Vector3(0, HAND_HEIGHT, -length * t) + jitter)
		_arc_mesh.surface_end()


# Projétil carregando: a pedra/gelo cresce na mão.
func _update_charge(active: bool) -> void:
	_charge.visible = active
	if not active:
		return
	var elements := _elements()
	var element: int = E.Type.ICE if E.Type.ICE in elements else E.Type.EARTH
	if element != _charge_element:
		_charge_element = element
		_charge.material_override = Vfx.glow_material(E.COLORS[element], 0.6 if element == E.Type.EARTH else 2.0)
	_charge.scale = Vector3.ONE * (0.35 + 0.6 * player.fx_length)
	_charge.rotation.y += 0.1
