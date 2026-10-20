# Feitiços especiais: receitas próprias, montadas na fila e lançadas com uma tecla.
# A ordem dos elementos não importa. Lógica pura, para ser testável.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

const SPECIALS := {
	"meteor": {
		"label": "Meteoro", "cooldown": 20.0,
		"recipe": [E.Type.FIRE, E.Type.EARTH, E.Type.FIRE, E.Type.EARTH],
		"description": "cai no cursor: Fogo + Terra em área (cuidado com os aliados)",
	},
	"storm": {
		"label": "Tempestade", "cooldown": 25.0,
		"recipe": [E.Type.COLD, E.Type.LIGHTNING, E.Type.COLD, E.Type.LIGHTNING],
		"description": "raios caem nos inimigos próximos por 5 s",
	},
	"frost": {
		"label": "Inverno", "cooldown": 30.0,
		"recipe": [E.Type.COLD, E.Type.SHIELD, E.Type.COLD],
		"description": "congela os inimigos num raio de 10 m",
	},
	"teleport": {
		"label": "Teleporte", "cooldown": 8.0,
		"recipe": [E.Type.ARCANE, E.Type.LIGHTNING, E.Type.ARCANE],
		"description": "salta até o cursor (até 10 m)",
	},
	"blessing": {
		"label": "Bênção", "cooldown": 40.0,
		"recipe": [E.Type.LIFE, E.Type.SHIELD, E.Type.LIFE],
		"description": "revive e cura todos os magos",
	},
}
const ORDER := ["meteor", "storm", "frost", "teleport", "blessing"]


static func match_special(elements: Array) -> String:
	var queue := elements.duplicate()
	queue.sort()
	for id in ORDER:
		var recipe: Array = SPECIALS[id].recipe.duplicate()
		recipe.sort()
		if recipe == queue:
			return id
	return ""
