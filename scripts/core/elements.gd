# Tabela de elementos: nomes, cores, dano e regras de combinação.
# Todos os números aqui são nossos e podem ser ajustados livremente.
extends RefCounted

enum Type { WATER, LIFE, SHIELD, COLD, LIGHTNING, ARCANE, EARTH, FIRE, STEAM, ICE }

const NONE := -1

const NAMES := {
	Type.WATER: "Água",
	Type.LIFE: "Vida",
	Type.SHIELD: "Escudo",
	Type.COLD: "Frio",
	Type.LIGHTNING: "Raio",
	Type.ARCANE: "Arcano",
	Type.EARTH: "Terra",
	Type.FIRE: "Fogo",
	Type.STEAM: "Vapor",
	Type.ICE: "Gelo",
}

const COLORS := {
	Type.WATER: Color(0.2, 0.5, 1.0),
	Type.LIFE: Color(0.3, 1.0, 0.4),
	Type.SHIELD: Color(1.0, 0.9, 0.5),
	Type.COLD: Color(0.8, 0.95, 1.0),
	Type.LIGHTNING: Color(0.8, 0.5, 1.0),
	Type.ARCANE: Color(1.0, 0.2, 0.4),
	Type.EARTH: Color(0.55, 0.4, 0.25),
	Type.FIRE: Color(1.0, 0.45, 0.1),
	Type.STEAM: Color(0.85, 0.85, 0.85),
	Type.ICE: Color(0.6, 0.85, 1.0),
}

# Dano por acerto (projétil/área) ou por segundo (spray/beam/arco).
# Valor negativo cura.
const DAMAGE := {
	Type.WATER: 4.0,
	Type.LIFE: -30.0,
	Type.SHIELD: 0.0,
	Type.COLD: 10.0,
	Type.LIGHTNING: 30.0,
	Type.ARCANE: 35.0,
	Type.EARTH: 40.0,
	Type.FIRE: 15.0,
	Type.STEAM: 20.0,
	Type.ICE: 25.0,
}

# Pares que se anulam quando entram juntos na fila.
const OPPOSITES := [
	[Type.WATER, Type.LIGHTNING],
	[Type.LIFE, Type.ARCANE],
	[Type.FIRE, Type.COLD],
	[Type.EARTH, Type.LIGHTNING],
	[Type.SHIELD, Type.SHIELD],
	[Type.FIRE, Type.ICE],
	[Type.COLD, Type.STEAM],
]

# Pares que se fundem em um terceiro elemento: [a, b, resultado].
const FUSIONS := [
	[Type.WATER, Type.FIRE, Type.STEAM],
	[Type.WATER, Type.COLD, Type.ICE],
]


static func cancels(a: int, b: int) -> bool:
	for pair in OPPOSITES:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


static func fuse(a: int, b: int) -> int:
	for rule in FUSIONS:
		if (rule[0] == a and rule[1] == b) or (rule[0] == b and rule[1] == a):
			return rule[2]
	return NONE


static func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
