# Decide a forma do feitiço a partir dos elementos na fila. Lógica pura.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

enum Shape { NONE, BARRIER, PROJECTILE, BEAM, ARC, SPRAY }

const SHAPE_NAMES := {
	Shape.NONE: "—",
	Shape.BARRIER: "Barreira",
	Shape.PROJECTILE: "Projétil",
	Shape.BEAM: "Raio contínuo",
	Shape.ARC: "Arco elétrico",
	Shape.SPRAY: "Spray",
}


# A ordem dos testes define a prioridade de cada elemento.
static func resolve_shape(elements: Array) -> int:
	if elements.is_empty():
		return Shape.NONE
	if E.Type.SHIELD in elements:
		return Shape.BARRIER
	if E.Type.EARTH in elements or E.Type.ICE in elements:
		return Shape.PROJECTILE
	if E.Type.ARCANE in elements or E.Type.LIFE in elements:
		return Shape.BEAM
	if E.Type.LIGHTNING in elements:
		return Shape.ARC
	return Shape.SPRAY
