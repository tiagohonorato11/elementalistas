# Barra de vida sobre uma unidade (sempre virada para a câmera).
# Verde: seu time; vermelha: inimigos; amarela: monstros neutros da selva.
# Só visual: lê o nó Health do pai, que é sincronizado.
extends Node3D

const Combat = preload("res://scripts/core/combat.gd")
const Vfx = preload("res://scripts/vfx/vfx.gd")

const ALLY := Color(0.3, 0.95, 0.35)
const ENEMY := Color(1.0, 0.25, 0.2)
const NEUTRAL := Color(1.0, 0.85, 0.2)
const BACK := Color(0.05, 0.05, 0.05)

var width := 1.2
var height_above := 2.3
var unit: Node
var health: Node
var _fill: MeshInstance3D
var _fill_mesh := QuadMesh.new()
var _shown_ratio := -1.0
var _color_set := false


func _ready() -> void:
	unit = get_parent()
	health = unit.get_node_or_null("Health")
	position.y = height_above
	var back := MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(width + 0.08, 0.2)
	back.mesh = back_mesh
	back.material_override = _material(BACK, 0)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	_fill = MeshInstance3D.new()
	_fill.mesh = _fill_mesh
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)


func _material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = priority
	return material


# Cor relativa a quem está olhando (o personagem local deste PC).
func _pick_color() -> Color:
	var team := Combat.team_of(unit)
	if team == Combat.NEUTRAL:
		return NEUTRAL
	var main := unit.get_parent()
	var viewer = main.get("local_player") if main != null else null
	var my_team: int = viewer.team if viewer != null else Combat.BLUE
	return ALLY if team == my_team else ENEMY


func _process(_delta: float) -> void:
	if health == null:
		return
	if not _color_set and unit.get_parent() != null and unit.get_parent().get("local_player") != null:
		_fill.material_override = _material(_pick_color(), 1)
		_color_set = true
	elif _fill.material_override == null:
		_fill.material_override = _material(_pick_color(), 1)
	visible = not health.dead and health.hp < health.max_hp or unit.is_in_group("players") and not health.dead
	var ratio := clampf(health.hp / maxf(health.max_hp, 1.0), 0.0, 1.0)
	if not is_equal_approx(ratio, _shown_ratio):
		_shown_ratio = ratio
		_fill_mesh.size = Vector2(maxf(width * ratio, 0.001), 0.14)
		_fill_mesh.center_offset = Vector3(-width * (1.0 - ratio) / 2.0, 0, 0)
