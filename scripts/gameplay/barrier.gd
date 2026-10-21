# Barreira (Escudo): parede temporária que bloqueia movimento e projéteis.
# - Escudo + Terra: muro de pedra, mais grosso e duradouro.
# - Escudo + outros elementos: parede elemental que aplica esses elementos
#   (por segundo) em quem encostar nela — aliados também. Vida cura.
# Em rede: o host aplica os efeitos e remove a barreira; ela some para todos.
extends StaticBody3D

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const LIFETIME := 6.0
const STONE_LIFETIME := 12.0
const SIZE := Vector3(3.0, 2.0, 0.4)
const STONE_SIZE := Vector3(3.0, 2.2, 0.9)
const HAZARD_MARGIN := Vector3(1.2, 0.5, 1.2)

var elements: Array = []
var team := Combat.NEUTRAL
var hazard: Array = []
var area: Area3D


func setup(p_elements: Array, p_team := Combat.NEUTRAL) -> void:
	elements = p_elements
	team = p_team


func _ready() -> void:
	var stone := E.Type.EARTH in elements
	hazard = elements.filter(func(element): return element != E.Type.SHIELD and element != E.Type.EARTH)
	var size := STONE_SIZE if stone else SIZE

	var color := Color(1.0, 0.9, 0.5, 0.6)
	if not hazard.is_empty():
		color = E.COLORS[hazard[0]]
		color.a = 0.65
	elif stone:
		color = E.COLORS[E.Type.EARTH]

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	collision.position.y = size.y / 2.0
	add_child(collision)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y / 2.0
	if stone:
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.1)
		material.roughness = 1.0
		mesh.material_override = material
	else:
		# Escudo: parede translúcida que brilha na cor do elemento.
		mesh.material_override = Vfx.glow_material(Color(color, 1.0), 1.2, 0.35)
	add_child(mesh)
	# Paredes elementais soltam partículas do elemento ao longo do comprimento.
	for element in hazard.slice(0, 2):
		var particles := Vfx.emitter(element, {"amount": 50, "lifetime": 0.7, "speed": 1.2,
			"box": Vector3(size.x / 2.0, size.y / 3.0, size.z), "size_scale": 1.2})
		particles.position.y = size.y / 3.0
		particles.emitting = true
		add_child(particles)
	Vfx.burst(get_parent(), global_position + Vector3.UP, hazard[0] if not hazard.is_empty() else E.Type.SHIELD, 20, 1.0, 2.0)
	Audio.play("stone_up" if stone else "shield_up", self)

	if not multiplayer.is_server():
		return
	get_tree().create_timer(STONE_LIFETIME if stone else LIFETIME).timeout.connect(queue_free)
	if not hazard.is_empty():
		area = Area3D.new()
		var area_shape := CollisionShape3D.new()
		var area_box := BoxShape3D.new()
		area_box.size = size + HAZARD_MARGIN
		area_shape.shape = area_box
		area_shape.position.y = size.y / 2.0
		area.add_child(area_shape)
		add_child(area)


func _physics_process(delta: float) -> void:
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		var target_health = body.get_node_or_null("Health")
		var hit_elements := Combat.filter_elements(team, body, hazard)
		if target_health != null and not hit_elements.is_empty():
			target_health.apply_elements(hit_elements, delta)
