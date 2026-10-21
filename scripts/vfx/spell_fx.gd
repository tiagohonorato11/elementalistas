# Efeito do Raio laser (skill E do Mago) de um personagem (filho dele): feixe
# brilhante com partículas e som contínuo. Lê fx_shape/fx_elements/fx_length,
# que o host sincroniza: funciona igual em todos os PCs.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const SpellResolver = preload("res://scripts/core/spell_resolver.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const HAND_HEIGHT := 1.1
# Camada de som de cada elemento por cima do zumbido do feixe.
const ELEMENT_SOUNDS := {
	E.Type.FIRE: "spray_fire", E.Type.WATER: "spray_water", E.Type.COLD: "spray_cold",
	E.Type.STEAM: "spray_steam", E.Type.ICE: "spray_cold", E.Type.LIGHTNING: "arc",
}

var player: Node
var _beam: MeshInstance3D
var _beam_particles: GPUParticles3D
var _beam_key := ""
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


func _elements() -> Array:
	var elements: Array = player.fx_elements
	return elements if not elements.is_empty() else [player.fx_element]


func _process(_delta: float) -> void:
	var active: bool = player.fx_shape == SpellResolver.Shape.BEAM
	_update_beam(active)
	_update_sound(active)


func _update_beam(active: bool) -> void:
	_beam.visible = active
	if _beam_particles != null:
		_beam_particles.emitting = active
	if not active:
		return
	var elements := _elements()
	var key := str(elements)
	if key != _beam_key:
		_beam_key = key
		_beam.material_override = Vfx.glow_material(Vfx.mix_color(elements), 3.0, 0.85)
		if _beam_particles != null:
			_beam_particles.queue_free()
		_beam_particles = Vfx.emitter(elements[0], {"amount": 40, "lifetime": 0.4, "speed": 0.6, "spread": 180.0, "box": Vector3.ONE})
		add_child(_beam_particles)
	var length := maxf(player.fx_length, 0.1)
	var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.03)
	_beam.scale = Vector3(pulse, length, pulse)
	_beam.position = Vector3(0, HAND_HEIGHT, -length / 2.0)
	_beam_particles.position = _beam.position
	(_beam_particles.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.15, 0.15, length / 2.0)


# Zumbido do feixe (Vida: acorde; o resto: arcano) + uma camada por elemento.
func _update_sound(active: bool) -> void:
	var wanted := {}
	if active:
		var elements := _elements()
		wanted["beam_life" if E.Type.LIFE in elements else "beam_arcane"] = true
		for element in elements:
			if ELEMENT_SOUNDS.has(element):
				wanted[ELEMENT_SOUNDS[element]] = true
	for id in wanted:
		if not _loops.has(id):
			_loops[id] = Audio.make_loop(id, self, -3.0)
	for id in _loops:
		var loop: Node = _loops[id]
		if loop != null and loop.playing != wanted.has(id):
			loop.playing = wanted.has(id)
