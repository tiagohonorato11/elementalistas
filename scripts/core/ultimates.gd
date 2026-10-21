# Ultimates (tecla R): o elemento que mais aparece na carga decide qual sai
# (no empate, o que entrou primeiro). Os outros elementos da carga vão junto,
# como reforço. Lógica pura, para ser testável.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

const ULTIMATES := {
	"meteor": {"label": "Meteoro", "description": "cai no cursor: Fogo + Terra em área (cuidado com os aliados)"},
	"storm": {"label": "Tempestade", "description": "raios caem nos inimigos próximos por 5 s"},
	"frost": {"label": "Inverno", "description": "congela os inimigos num raio de 10 m"},
	"blessing": {"label": "Bênção", "description": "revive e cura o time"},
	"quake": {"label": "Terremoto", "description": "dano e atordoamento nos inimigos em 7 m"},
	"cataclysm": {"label": "Cataclismo", "description": "grande explosão arcana no cursor depois de 1 s"},
	"tide": {"label": "Maremoto", "description": "onda à frente que molha e empurra forte"},
	"fortress": {"label": "Fortaleza", "description": "anel de barreiras e escudo no time próximo"},
	"eclipse": {"label": "Eclipse", "description": "desfaz proteções e drena a mana dos inimigos em 9 m"},
	"singularity": {"label": "Singularidade", "description": "suga os inimigos para o cursor e atordoa"},
	"smokescreen": {"label": "Cortina de fumaça", "description": "cega os inimigos em 8 m e esconde o seu time"},
}
const BY_ELEMENT := {
	E.Type.FIRE: "meteor",
	E.Type.LIGHTNING: "storm",
	E.Type.COLD: "frost",
	E.Type.ICE: "frost",
	E.Type.LIFE: "blessing",
	E.Type.EARTH: "quake",
	E.Type.ARCANE: "cataclysm",
	E.Type.WATER: "tide",
	E.Type.STEAM: "tide",
	E.Type.SHIELD: "fortress",
	E.Type.VOID: "eclipse",
	E.Type.GRAVITY: "singularity",
	E.Type.SMOKE: "smokescreen",
}


# Elemento dominante da carga (o mais repetido; no empate, o primeiro). -1 se vazia.
static func dominant(charge: Array) -> int:
	var best := E.NONE
	var best_count := 0
	for element in charge:
		var count := charge.count(element)
		if count > best_count:
			best = element
			best_count = count
	return best


# Id do ultimate que a carga gera ("" se vazia).
static func resolve(charge: Array) -> String:
	var element := dominant(charge)
	return BY_ELEMENT.get(element, "")


static func label(id: String) -> String:
	return ULTIMATES[id].label if ULTIMATES.has(id) else "—"
