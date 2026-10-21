# Vida + estados (molhado, queimando, resfriado, congelado, escudo, proteção) e interações.
extends Node

const E = preload("res://scripts/core/elements.gd")

signal died
signal revived
signal damaged(amount: float)   # depois da armadura; usado pela selva para provocar os monstros

const BURN_DPS := 8.0
const WET_TIME := 4.0
const BURN_TIME := 4.0
const CHILL_TIME := 3.0
const SELF_SHIELD_TIME := 5.0
const REVIVE_FRACTION := 0.5
const FREEZE_TIME := 2.5
const WARD_TIME := 10.0

@export var max_hp := 100.0
# Quem pode ser levantado com Vida depois de cair (os magos).
@export var revivable := false
# Multiplicador por elemento (ex.: {Fogo: 0.0} = imune). Ausente = 1.0.
var resistances := {}
# Fração de todo dano recebido que é ignorada (ex.: 0.25 do Lutador).
var armor := 0.0
# Estruturas (torres, inibidores, nexus): só levam dano; não queimam, não
# congelam e não são curadas por Vida.
var immune_status := false
# Não leva dano (ex.: torre interna enquanto a externa estiver de pé).
var invulnerable := false

var hp := 0.0
var wet := 0.0
var burning := 0.0
var chilled := 0.0
var shielded := 0.0
var frozen := 0.0            # não anda nem ataca
var ward := 0.0              # tempo restante da proteção elemental
var ward_elements: Array = []
var dead := false


func _ready() -> void:
	reset()


func reset() -> void:
	hp = max_hp
	wet = 0.0
	burning = 0.0
	chilled = 0.0
	shielded = 0.0
	frozen = 0.0
	ward = 0.0
	ward_elements = []
	dead = false


# scale = 1.0 para acertos únicos; scale = delta para efeitos contínuos.
func apply_elements(elements: Array, scale: float) -> void:
	for element in elements:
		_apply(element, scale)


# Dano direto, sem elemento (ex.: golpe corpo a corpo).
func damage(amount: float) -> void:
	_change_hp(-amount)


# Cura direta (ex.: fonte da base no MOBA). Não passa pela armadura.
func heal(amount: float) -> void:
	_change_hp(absf(amount))


# Proteção elemental: imune aos elementos dados por WARD_TIME segundos.
func set_ward(elements: Array) -> void:
	ward_elements = elements.duplicate()
	ward = WARD_TIME


func freeze(duration: float) -> void:
	if dead:
		return
	burning = 0.0
	frozen = maxf(frozen, duration)


func revive() -> void:
	if not dead:
		return
	reset()
	hp = max_hp * REVIVE_FRACTION
	revived.emit()


func _apply(element: int, scale: float) -> void:
	if dead:
		if element == E.Type.LIFE and revivable:
			revive()
		return
	if ward > 0.0 and element in ward_elements:
		return
	var multiplier: float = resistances.get(element, 1.0)
	if multiplier <= 0.0:
		return
	var amount: float = E.DAMAGE[element] * scale * multiplier
	if immune_status:
		if amount > 0.0:
			_change_hp(-amount)
		return
	if element == E.Type.WATER or element == E.Type.STEAM:
		burning = 0.0
		wet = WET_TIME
	elif element == E.Type.FIRE:
		# Fogo descongela; em alvo molhado, seca em vez de incendiar.
		if frozen > 0.0:
			frozen = 0.0
		elif wet > 0.0:
			wet = 0.0
		else:
			burning = BURN_TIME
		chilled = 0.0
	elif element == E.Type.COLD or element == E.Type.ICE:
		burning = 0.0
		chilled = CHILL_TIME
		# Frio em alvo molhado congela.
		if wet > 0.0:
			wet = 0.0
			frozen = FREEZE_TIME
	elif element == E.Type.LIGHTNING and wet > 0.0:
		amount *= 2.0
	elif element == E.Type.EARTH and frozen > 0.0:
		# Terra estilhaça quem está congelado.
		amount *= 2.0
		frozen = 0.0
	_change_hp(-amount)


func _change_hp(delta_hp: float) -> void:
	if dead:
		return
	if delta_hp < 0.0:
		if invulnerable:
			return
		delta_hp *= 1.0 - armor
		if shielded > 0.0:
			delta_hp *= 0.5
		damaged.emit(-delta_hp)
	hp = clampf(hp + delta_hp, 0.0, max_hp)
	if hp <= 0.0:
		dead = true
		died.emit()


func _process(delta: float) -> void:
	# Em rede, só o host simula; os outros recebem os valores sincronizados.
	if is_inside_tree() and not multiplayer.is_server():
		return
	wet = maxf(wet - delta, 0.0)
	chilled = maxf(chilled - delta, 0.0)
	shielded = maxf(shielded - delta, 0.0)
	frozen = maxf(frozen - delta, 0.0)
	ward = maxf(ward - delta, 0.0)
	if burning > 0.0:
		burning = maxf(burning - delta, 0.0)
		_change_hp(-BURN_DPS * delta)


func status_text() -> String:
	var parts := PackedStringArray()
	if wet > 0.0:
		parts.append("molhado")
	if burning > 0.0:
		parts.append("queimando")
	if chilled > 0.0:
		parts.append("resfriado")
	if frozen > 0.0:
		parts.append("congelado")
	if shielded > 0.0:
		parts.append("protegido")
	if ward > 0.0:
		var names := PackedStringArray()
		for element in ward_elements:
			names.append(E.NAMES[element])
		parts.append("imune a " + "/".join(names))
	return ", ".join(parts)
