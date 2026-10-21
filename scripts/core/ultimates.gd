# Ultimates (tecla R), voláteis: dependem da combinação da carga.
# - 3 elementos iguais: a versão MEGA daquele elemento.
# - Senão: o ultimate do elemento que mais aparece (no empate, o que entrou
#   primeiro); os outros elementos vão junto como reforço e cada um deixa no
#   local a zona dele (a mesma do Mini meteoro, ver zone.gd).
# Lógica pura, para ser testável.
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
	"blood_moon": {"label": "Lua de sangue", "description": "inimigos em 9 m sangram; você cura metade do dano"},
	# Versões MEGA (3 elementos iguais).
	"mega_fire": {"label": "Chuva de meteoros", "description": "5 meteoros caem em volta do cursor"},
	"mega_lightning": {"label": "Tempestade suprema", "description": "8 s de raios que saltam entre os inimigos"},
	"mega_cold": {"label": "Era do gelo", "description": "congela os inimigos em 15 m e deixa o chão gelado"},
	"mega_life": {"label": "Renascer", "description": "revive o time com a vida cheia e acelera"},
	"mega_earth": {"label": "Fenda", "description": "rachadura à frente que atordoa 2 s e ergue paredes de pedra"},
	"mega_arcane": {"label": "Supernova", "description": "carrega 1,5 s e explode tudo ao seu redor"},
	"mega_water": {"label": "Tsunami", "description": "onda gigante à frente que arrasta tudo"},
	"mega_shield": {"label": "Bastião", "description": "o time próximo fica invulnerável por 3 s"},
	"mega_void": {"label": "Apagão", "description": "inimigos em 12 m ficam 3 s sem skills e sem mana"},
	"mega_gravity": {"label": "Buraco negro", "description": "vórtice no cursor que suga e fere por 4 s"},
	"mega_smoke": {"label": "Mega fumaça", "description": "nuvem enorme: os inimigos ficam cegos e sem visão por 3 s"},
	"mega_blood": {"label": "Banquete de sangue", "description": "inimigos em 10 m sangram; você cura todo o dano e o time rouba vida"},
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
	E.Type.BLOOD: "blood_moon",
}
const MEGA_BY_ELEMENT := {
	E.Type.FIRE: "mega_fire",
	E.Type.LIGHTNING: "mega_lightning",
	E.Type.COLD: "mega_cold",
	E.Type.ICE: "mega_cold",
	E.Type.LIFE: "mega_life",
	E.Type.EARTH: "mega_earth",
	E.Type.ARCANE: "mega_arcane",
	E.Type.WATER: "mega_water",
	E.Type.STEAM: "mega_water",
	E.Type.SHIELD: "mega_shield",
	E.Type.VOID: "mega_void",
	E.Type.GRAVITY: "mega_gravity",
	E.Type.SMOKE: "mega_smoke",
	E.Type.BLOOD: "mega_blood",
}
const MEGA_SIZE := 3


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


static func is_mega(charge: Array) -> bool:
	return charge.size() == MEGA_SIZE and charge.count(charge[0]) == MEGA_SIZE


# Id do ultimate que a carga gera ("" se vazia).
static func resolve(charge: Array) -> String:
	if is_mega(charge):
		return MEGA_BY_ELEMENT.get(charge[0], "")
	return BY_ELEMENT.get(dominant(charge), "")


# Elementos (sem repetir) que deixam zona no local do ultimate: os que não são o dominante.
static func zone_elements(charge: Array) -> Array:
	if is_mega(charge):
		return []
	var main := dominant(charge)
	var result: Array = []
	for element in charge:
		if element != main and not (element in result):
			result.append(element)
	return result


static func label(id: String) -> String:
	return ULTIMATES[id].label if ULTIMATES.has(id) else "—"
