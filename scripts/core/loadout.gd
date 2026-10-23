# Escolha de elementos antes da partida: 3 elementos diferentes entre os 12,
# sem pares opostos (eles se anulariam na carga). O 1º fica na tecla D, o 2º
# no F e o 3º no G. Lógica pura, para ser testável.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")
const ElementQueue = preload("res://scripts/core/element_queue.gd")

const SIZE := 3
const BASIC := [E.Type.WATER, E.Type.LIFE, E.Type.SHIELD, E.Type.COLD,
	E.Type.LIGHTNING, E.Type.ARCANE, E.Type.EARTH, E.Type.FIRE,
	E.Type.VOID, E.Type.GRAVITY, E.Type.SMOKE, E.Type.BLOOD]
const DEFAULTS := {
	"mage": [E.Type.FIRE, E.Type.LIGHTNING, E.Type.ARCANE],
	"assassin": [E.Type.ARCANE, E.Type.COLD, E.Type.EARTH],
	"fighter": [E.Type.FIRE, E.Type.EARTH, E.Type.SHIELD],
}


# Todas as cargas que dá para montar com 1 a 3 toques nas teclas D F G (com
# fusões, ex.: Água + Fogo = Vapor). Cada item: {"keys": índices 0..2 na ordem
# apertada, "charge": a carga que resulta}. Sem cargas repetidas; das mais
# curtas para as mais longas.
static func charges(elements: Array) -> Array:
	var result: Array = []
	var seen := {}
	var presses: Array = [[]]
	for size in ElementQueue.MAX_SIZE:
		var longer: Array = []
		for keys in presses:
			var last: int = keys[-1] if not keys.is_empty() else 0
			for slot in range(last, elements.size()):
				longer.append(keys + [slot])
		presses = longer
		for keys in presses:
			var queue := ElementQueue.new()
			for slot in keys:
				queue.add(elements[slot])
			var sorted := queue.elements.duplicate()
			sorted.sort()
			if queue.is_empty() or seen.has(str(sorted)):
				continue
			seen[str(sorted)] = true
			result.append({"keys": keys, "charge": queue.elements.duplicate()})
	return result


static func default_for(class_id: String) -> Array:
	return DEFAULTS.get(class_id, DEFAULTS.mage).duplicate()


# "" se a escolha vale; senão, o motivo (mostrado no lobby).
static func problem(elements: Array) -> String:
	if elements.size() != SIZE:
		return "Escolha %d elementos." % SIZE
	for element in elements:
		if not (element in BASIC):
			return "Elemento inválido."
		if elements.count(element) > 1:
			return "Os elementos precisam ser diferentes."
	for i in elements.size():
		for j in range(i + 1, elements.size()):
			if E.cancels(elements[i], elements[j]):
				return "%s e %s são opostos." % [E.NAMES[elements[i]], E.NAMES[elements[j]]]
	return ""


static func is_valid(elements: Array) -> bool:
	return problem(elements).is_empty()


# Elementos que ainda dá para somar à escolha parcial `chosen` (botões do lobby).
static func can_add(chosen: Array, element: int) -> bool:
	if chosen.size() >= SIZE or element in chosen:
		return false
	for other in chosen:
		if E.cancels(other, element):
			return false
	return true


# Sorteio de uma escolha válida (bots).
static func random() -> Array:
	var chosen: Array = []
	var pool := BASIC.duplicate()
	pool.shuffle()
	for element in pool:
		if can_add(chosen, element):
			chosen.append(element)
	return chosen


# Escolha válida a partir de qualquer coisa (dados salvos ou vindos da rede).
static func sanitize(elements, class_id: String) -> Array:
	if elements is Array:
		var list: Array = []
		for element in elements:
			list.append(int(element))
		if is_valid(list):
			return list
	return default_for(class_id)
