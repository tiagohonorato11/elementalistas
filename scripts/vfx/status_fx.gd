# Efeitos visuais dos estados de uma unidade (filho do personagem/inimigo/tropa).
# Lê o nó Health do pai, que já é sincronizado pela rede: funciona em todos os PCs.
extends Node3D

const E = preload("res://scripts/core/elements.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

var height := 2.0      # altura da unidade (posiciona chamas, bolha etc.)
var radius := 0.5
var health: Node
var _burning: GPUParticles3D
var _wet: GPUParticles3D
var _chilled: GPUParticles3D
var _blinded: GPUParticles3D
var _bleeding: GPUParticles3D
var _ice: MeshInstance3D
var _bubble: MeshInstance3D
var _ward: MeshInstance3D


func _ready() -> void:
	health = get_parent().get_node_or_null("Health")
	var body_box := Vector3(radius, height * 0.4, radius)
	_burning = _add_emitter(E.Type.FIRE, {"amount": 28, "lifetime": 0.55, "speed": 1.8, "box": body_box, "size_scale": 1.5})
	_wet = _add_emitter(E.Type.WATER, {"amount": 8, "lifetime": 0.6, "speed": 0.3, "box": body_box, "size_scale": 0.6})
	_chilled = _add_emitter(E.Type.COLD, {"amount": 10, "lifetime": 1.0, "speed": 0.4, "box": body_box, "size_scale": 0.8})
	# Cego: nuvem de fumaça em volta da cabeça.
	_blinded = _add_emitter(E.Type.SMOKE, {"amount": 14, "lifetime": 1.2, "speed": 0.3, "sphere": radius * 1.2, "size_scale": 1.0})
	_blinded.position.y = height * 0.85
	# Sangrando: gotas vermelhas pingando.
	_bleeding = _add_emitter(E.Type.BLOOD, {"amount": 10, "lifetime": 0.6, "speed": 0.4, "box": body_box, "size_scale": 0.8})

	_ice = MeshInstance3D.new()
	var ice_mesh := BoxMesh.new()
	ice_mesh.size = Vector3(radius * 2.6, height * 1.05, radius * 2.6)
	_ice.mesh = ice_mesh
	_ice.position.y = height * 0.5
	_ice.material_override = Vfx.glow_material(Color(0.65, 0.9, 1.0), 1.2, 0.65)
	_ice.visible = false
	add_child(_ice)

	_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = maxf(radius * 2.0, height * 0.65)
	sphere.height = sphere.radius * 2.0
	_bubble.mesh = sphere
	_bubble.position.y = height * 0.5
	_bubble.material_override = Vfx.glow_material(Color(1.0, 0.9, 0.5), 0.8, 0.18)
	_bubble.visible = false
	add_child(_bubble)

	_ward = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 1.6
	ring.outer_radius = radius * 1.9
	_ward.mesh = ring
	_ward.position.y = 0.1
	_ward.visible = false
	add_child(_ward)


func _add_emitter(element: int, options: Dictionary) -> GPUParticles3D:
	var particles := Vfx.emitter(element, options)
	particles.position.y = height * 0.5
	particles.emitting = false
	add_child(particles)
	return particles


func _process(delta: float) -> void:
	if health == null:
		return
	var alive: bool = not health.dead
	_set_emitting(_burning, alive and health.burning > 0.0)
	_set_emitting(_wet, alive and health.wet > 0.0)
	_set_emitting(_chilled, alive and health.chilled > 0.0 and health.frozen <= 0.0)
	_set_emitting(_blinded, alive and health.blinded > 0.0)
	_set_emitting(_bleeding, alive and health.get("bleeding") > 0.0)
	_ice.visible = alive and health.frozen > 0.0
	_bubble.visible = alive and (health.shielded > 0.0 or health.barrier_hp > 0.0)
	var warded: bool = alive and health.ward > 0.0 and not health.ward_elements.is_empty()
	if warded and not _ward.visible:
		_ward.material_override = Vfx.glow_material(Vfx.mix_color(health.ward_elements), 1.5, 0.8)
	_ward.visible = warded
	if warded:
		_ward.rotation.y += delta * 2.0


func _set_emitting(particles: GPUParticles3D, on: bool) -> void:
	if particles.emitting != on:
		particles.emitting = on
