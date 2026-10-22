# Indicador de mira no chão (só no PC do jogador), enquanto ele segura uma skill:
# - "line": faixa na direção do mouse (Orbe, Adaga, Investida, Fenda), com um
#   círculo no fim quando a Orbe vai explodir em área;
# - "circle": área no cursor (Mini meteoro, Meteoro...), com o anel de alcance;
#   "fixed": a área fica sempre na distância máxima (Passo sombrio);
# - "self": área em volta do personagem (Inverno, Supernova, bolha...);
# - "cone": leque à frente (Maremoto, Tsunami).
# Também marca a unidade sob o mouse (alvo do W): verde aliado, vermelho inimigo.
extends Node3D

const Vfx = preload("res://scripts/vfx/vfx.gd")

const ALLY := Color(0.35, 1.0, 0.45)
const ENEMY := Color(1.0, 0.3, 0.25)

var _range_ring: MeshInstance3D
var _area: MeshInstance3D
var _edge: MeshInstance3D
var _line: MeshInstance3D
var _cone: MeshInstance3D
var _cone_mesh := ImmediateMesh.new()
var _cone_key := Vector2.ZERO
var _hover: MeshInstance3D
var _color := Color.WHITE


func _ready() -> void:
	top_level = true
	_range_ring = _torus(0.97)
	_edge = _torus(0.93)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	_area = _mesh(disc)
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	_line = _mesh(box)
	_cone = _mesh(_cone_mesh)
	_hover = _torus(0.8)
	hide_shape()
	_hover.visible = false


func _torus(inner: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = 1.0
	torus.rings = 48
	var ring := _mesh(torus)
	ring.scale = Vector3.ONE
	return ring


func _mesh(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func hide_shape() -> void:
	for node in [_range_ring, _area, _edge, _line, _cone]:
		node.visible = false


func _paint(color: Color) -> void:
	if color == _color and _area.material_override != null:
		return
	_color = color
	_area.material_override = Vfx.glow_material(color, 0.8, 0.22)
	_line.material_override = Vfx.glow_material(color, 0.8, 0.3)
	_cone.material_override = Vfx.glow_material(color, 0.8, 0.22)
	_cone.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge.material_override = Vfx.glow_material(color, 2.0, 0.85)
	_range_ring.material_override = Vfx.glow_material(Color(1, 1, 1), 1.0, 0.35)


# Mostra a forma `shape` saindo de `origin` na direção de `aim` (pontos no chão).
func show_shape(shape: Dictionary, origin: Vector3, aim: Vector3, color: Color) -> void:
	hide_shape()
	if shape.is_empty():
		return
	_paint(color)
	origin.y = 0.0
	aim.y = 0.0
	var offset := aim - origin
	var direction := offset.normalized() if offset.length() > 0.05 else Vector3.FORWARD
	var yaw := atan2(direction.x, direction.z)
	match shape.type:
		"line":
			_place_line(origin, direction, yaw, shape.length, shape.width)
			if shape.get("end_radius", 0.0) > 0.0:
				_place_area(origin + direction * shape.length, shape.end_radius)
		"circle":
			var reach: float = shape.range
			var center := origin + direction * reach if shape.get("fixed", false) \
				else origin + offset.limit_length(reach)
			_place_area(center, shape.radius)
			_range_ring.visible = true
			_range_ring.global_position = origin + Vector3.UP * 0.05
			_range_ring.scale = Vector3(reach, 0.1, reach)
		"self":
			_place_area(origin, shape.radius)
		"cone":
			_place_cone(origin, yaw, shape.length, shape.angle)


func _place_area(center: Vector3, radius: float) -> void:
	_area.visible = true
	_area.global_position = center + Vector3.UP * 0.05
	_area.scale = Vector3(radius, 1.0, radius)
	_edge.visible = true
	_edge.global_position = center + Vector3.UP * 0.06
	_edge.scale = Vector3(radius, 0.1, radius)


func _place_line(origin: Vector3, direction: Vector3, yaw: float, length: float, width: float) -> void:
	_line.visible = true
	_line.global_position = origin + direction * (length / 2.0) + Vector3.UP * 0.05
	_line.rotation = Vector3(0.0, yaw, 0.0)
	_line.scale = Vector3(width, 1.0, length)


func _place_cone(origin: Vector3, yaw: float, length: float, angle: float) -> void:
	var key := Vector2(length, angle)
	if key != _cone_key:
		_cone_key = key
		_cone_mesh.clear_surfaces()
		_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 16
		for i in steps:
			var a := -angle + 2.0 * angle * i / steps
			var b := -angle + 2.0 * angle * (i + 1) / steps
			_cone_mesh.surface_add_vertex(Vector3.ZERO)
			_cone_mesh.surface_add_vertex(Vector3(sin(b), 0.0, cos(b)) * length)
			_cone_mesh.surface_add_vertex(Vector3(sin(a), 0.0, cos(a)) * length)
		_cone_mesh.surface_end()
	_cone.visible = true
	_cone.global_position = origin + Vector3.UP * 0.05
	_cone.rotation = Vector3(0.0, yaw, 0.0)


# Anel sob a unidade que está sob o mouse (null: esconde).
func show_hover(target: Node3D, ally: bool) -> void:
	_hover.visible = target != null
	if target == null:
		return
	var color := ALLY if ally else ENEMY
	if _hover.get_meta("color", Color.BLACK) != color:
		_hover.set_meta("color", color)
		_hover.material_override = Vfx.glow_material(color, 2.5, 0.9)
	_hover.global_position = Vector3(target.global_position.x, 0.08, target.global_position.z)
	_hover.scale = Vector3(1.0, 0.12, 1.0)
