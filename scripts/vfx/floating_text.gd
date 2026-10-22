# Números de dano e cura subindo de uma unidade, e avisos de estado ("Congelado!").
# Filho da barra de vida; lê o nó Health do pai, que é sincronizado, então funciona
# igual em todos os PCs. O dano de vários golpes seguidos é somado em um só número
# (a cada 0,2 s), na cor do último elemento que acertou; a cura (somada à parte)
# sobe em verde. Dano contínuo pequeno (queimadura, sangramento) junta até dar
# um número que valha a pena ler, ou até 1 s.
extends Node3D

const E = preload("res://scripts/core/elements.gd")

const FLUSH_TIME := 0.2
const RISE := 1.3
const LIFETIME := 0.9
const PLAIN_DAMAGE := Color(1.0, 0.92, 0.75)
const HEAL_COLOR := Color(0.35, 1.0, 0.45)
const BIG_HIT := 60.0
const MIN_SHOWN := 6.0         # abaixo disso, continua somando...
const MAX_HOLD := 1.0          # ...até no máximo 1 s
# Estados que ganham um aviso quando começam.
const STATES := {
	"frozen": ["Congelado!", Color(0.6, 0.9, 1.0)],
	"stunned": ["Atordoado!", Color(1.0, 0.85, 0.3)],
	"blinded": ["Cego!", Color(0.75, 0.75, 0.78)],
	"silenced": ["Silenciado!", Color(0.7, 0.4, 1.0)],
	"bleeding": ["Sangrando!", Color(0.95, 0.2, 0.25)],
	"vulnerable": ["Marcado!", Color(1.0, 0.5, 0.3)],
}

var health: Node
var unit: Node
var _last_hp := -1.0
var _pending_damage := 0.0
var _pending_heal := 0.0
var _timer := 0.0
var _held := 0.0
var _active := {}


func _process(delta: float) -> void:
	if health == null or not is_instance_valid(health):
		return
	if _last_hp < 0.0 or health.dead:
		_last_hp = health.hp
		_pending_damage = 0.0
		_pending_heal = 0.0
		return
	var change: float = health.hp - _last_hp
	if change < 0.0:
		_pending_damage -= change
	else:
		_pending_heal += change
	_last_hp = health.hp
	_timer -= delta
	_held += delta
	if _timer <= 0.0:
		_timer = FLUSH_TIME
		_flush()
	for id in STATES:
		var value = health.get(id)
		var on: bool = value != null and value > 0.0
		if on and not _active.get(id, false):
			_pop(STATES[id][0], STATES[id][1], 34, 0.4)
		_active[id] = on


func _flush() -> void:
	var waiting := _held < MAX_HOLD
	if waiting and _pending_damage < MIN_SHOWN and _pending_heal < MIN_SHOWN:
		return
	_held = 0.0
	var damage := _pending_damage
	var heal := _pending_heal
	_pending_damage = 0.0
	_pending_heal = 0.0
	if damage >= 1.0:
		var element: int = health.get("last_element") if health.get("last_element") != null else -1
		var color: Color = E.COLORS[element].lightened(0.25) if element >= 0 else PLAIN_DAMAGE
		_pop("%d" % roundi(damage), color, 44 if damage >= BIG_HIT else 34, 0.0)
	# Cura (vida cheia de uma vez, como renascer, não aparece).
	if heal >= 1.0 and heal < health.max_hp * 0.5:
		_pop("+%d" % roundi(heal), HEAL_COLOR, 34, 0.5 if damage >= 1.0 else 0.0)


func _pop(text: String, color: Color, size: int, lift: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.018
	label.outline_size = 10
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 2
	label.fixed_size = false
	add_child(label)
	label.position = Vector3(randf_range(-0.35, 0.35), lift, 0.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", lift + RISE, LIFETIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME).set_delay(LIFETIME * 0.45)
	tween.chain().tween_callback(label.queue_free)
