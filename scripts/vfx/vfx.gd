# Efeitos visuais: partículas e materiais por elemento, montados por código
# (sem texturas externas). Só visual: nada aqui afeta a lógica do jogo.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

# Estilo de cada elemento nas partículas.
# additive: brilha (fogo, raio, arcano, vida); gravity: puxão vertical; rise: sobe.
const STYLES := {
	E.Type.WATER: {"colors": [Color(0.35, 0.65, 1.0, 0.9), Color(0.2, 0.45, 1.0, 0.0)], "additive": false, "gravity": -9.0, "size": 0.18},
	E.Type.LIFE: {"colors": [Color(0.5, 1.0, 0.5, 1.0), Color(0.2, 1.0, 0.4, 0.0)], "additive": true, "gravity": 1.5, "size": 0.16},
	E.Type.SHIELD: {"colors": [Color(1.0, 0.92, 0.55, 0.9), Color(1.0, 0.8, 0.3, 0.0)], "additive": true, "gravity": 0.0, "size": 0.2},
	E.Type.COLD: {"colors": [Color(0.9, 0.97, 1.0, 0.9), Color(0.7, 0.9, 1.0, 0.0)], "additive": false, "gravity": -0.5, "size": 0.22},
	E.Type.LIGHTNING: {"colors": [Color(0.85, 0.7, 1.0, 1.0), Color(0.6, 0.35, 1.0, 0.0)], "additive": true, "gravity": 0.0, "size": 0.12},
	E.Type.ARCANE: {"colors": [Color(1.0, 0.25, 0.5, 1.0), Color(0.7, 0.05, 0.4, 0.0)], "additive": true, "gravity": 0.0, "size": 0.2},
	E.Type.EARTH: {"colors": [Color(0.6, 0.45, 0.3, 1.0), Color(0.45, 0.33, 0.22, 0.0)], "additive": false, "gravity": -12.0, "size": 0.2},
	E.Type.FIRE: {"colors": [Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.35, 0.05, 0.6), Color(0.3, 0.05, 0.0, 0.0)], "additive": true, "gravity": 3.0, "size": 0.3},
	E.Type.STEAM: {"colors": [Color(0.95, 0.95, 0.95, 0.7), Color(0.85, 0.85, 0.9, 0.0)], "additive": false, "gravity": 1.5, "size": 0.45},
	E.Type.ICE: {"colors": [Color(0.75, 0.95, 1.0, 1.0), Color(0.5, 0.8, 1.0, 0.0)], "additive": true, "gravity": -2.0, "size": 0.15},
}

static var _soft_texture: Texture2D
static var _materials := {}


# Círculo suave (branco no centro, transparente na borda) para as partículas.
static func soft_texture() -> Texture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.4, Color(1, 1, 1, 0.8))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_soft_texture = texture
	return _soft_texture


# Material de partícula (billboard, cor por vértice), aditivo ou com transparência.
static func particle_material(additive: bool) -> StandardMaterial3D:
	if _materials.has(additive):
		return _materials[additive]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = soft_texture()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.no_depth_test = false
	_materials[additive] = material
	return material


# Material sólido com brilho (núcleo de raios, projéteis, escudos).
static func glow_material(color: Color, energy := 2.0, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func color_ramp(colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, colors[0])
	gradient.set_color(1, colors[-1])
	for i in range(1, colors.size() - 1):
		gradient.add_point(float(i) / (colors.size() - 1), colors[i])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


# Emissor de partículas de um elemento. Opções (todas opcionais):
#   amount, lifetime, speed, spread (graus), direction, box (Vector3: emite numa caixa),
#   sphere (raio), size_scale, one_shot, explosiveness, local (coords locais).
static func emitter(element: int, options := {}) -> GPUParticles3D:
	var style: Dictionary = STYLES.get(element, STYLES[E.Type.FIRE])
	var particles := GPUParticles3D.new()
	particles.amount = options.get("amount", 24)
	particles.lifetime = options.get("lifetime", 0.6)
	particles.one_shot = options.get("one_shot", false)
	particles.explosiveness = options.get("explosiveness", 0.0)
	particles.local_coords = options.get("local", false)
	particles.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 10, 16))

	var process := ParticleProcessMaterial.new()
	process.direction = options.get("direction", Vector3.UP)
	process.spread = options.get("spread", 25.0)
	var speed: float = options.get("speed", 2.0)
	process.initial_velocity_min = speed * 0.7
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, style.gravity, 0)
	var size: float = style.size * options.get("size_scale", 1.0)
	process.scale_min = 0.6
	process.scale_max = 1.0
	process.color_ramp = color_ramp(style.colors)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.6))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1, 0.2))
	var curve_texture := CurveTexture.new()
	curve_texture.curve = scale_curve
	process.scale_curve = curve_texture
	if options.has("box"):
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = options.box
	elif options.has("sphere"):
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = options.sphere
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = particle_material(style.additive)
	particles.draw_pass_1 = quad
	return particles


# Explosão rápida que se remove sozinha (impactos, áreas, mortes).
static func burst(parent: Node, at: Vector3, element: int, amount := 30, radius := 0.4, speed := 4.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var particles := emitter(element, {
		"amount": amount, "lifetime": 0.7, "one_shot": true, "explosiveness": 0.95,
		"spread": 180.0, "speed": speed, "sphere": radius,
	})
	particles.position = parent.to_local(at) if parent is Node3D else at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	# Adiado: pode ser chamado enquanto o pai está removendo um filho (ex.: projétil sumindo).
	parent.add_child.call_deferred(particles)


# Cor média de uma lista de elementos (para núcleos de raios e paredes).
static func mix_color(elements: Array) -> Color:
	if elements.is_empty():
		return Color.WHITE
	var total := Color(0, 0, 0, 0)
	for element in elements:
		total += E.COLORS[element]
	return Color(total.r / elements.size(), total.g / elements.size(), total.b / elements.size())


# Anel brilhante no chão sob uma unidade (cor do jogador ou do time).
static func add_ring(parent: Node3D, color: Color, radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 24
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.04
	ring.material_override = glow_material(color, 1.6, 0.85)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	return ring
