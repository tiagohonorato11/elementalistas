# Fila de elementos do mago (até 5). Lógica pura, sem nós, para ser testável.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

const MAX_SIZE := 5

var elements: Array = []


func add(element: int) -> void:
	# 1) Um oposto na fila anula os dois.
	for i in elements.size():
		if E.cancels(elements[i], element):
			elements.remove_at(i)
			return
	# 2) Um par compatível se funde (ex.: Água + Fogo = Vapor).
	for i in elements.size():
		var fused := E.fuse(elements[i], element)
		if fused != E.NONE:
			elements[i] = fused
			return
	# 3) Senão, entra no fim da fila se houver espaço.
	if elements.size() < MAX_SIZE:
		elements.append(element)


func clear() -> void:
	elements.clear()


func is_empty() -> bool:
	return elements.is_empty()
