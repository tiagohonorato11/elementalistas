# Classes jogáveis. Todas usam a mesma fila de elementos; cada uma tem atributos,
# arma e habilidade próprias. Todos os números são nossos e podem ser ajustados.
extends RefCounted

const DEFAULT := "mage"
const ORDER := ["mage", "assassin", "fighter"]

const CLASSES := {
	"mage": {
		"label": "Mago",
		"description": "Feitiços com força total e recarga normal dos especiais. Habilidade: Escudo arcano.",
		"hp": 200.0, "speed": 5.0, "armor": 0.0,
		"spell_power": 1.0, "special_cooldown": 1.0,
		# charges = quantos golpes seguidos levam os elementos da fila.
		"weapon": {"damage": 20.0, "cooldown": 0.6, "range": 2.3, "angle": 1.05, "push": 4.0,
			"element_scale": 0.8, "charges": 1},
		"backstab": 1.0,
		"ability": "arcane_shield", "ability_label": "Escudo arcano", "ability_cooldown": 12.0,
	},
	"assassin": {
		"label": "Assassino",
		"description": "Rápido e frágil. Adagas levam os elementos por 3 golpes; pelas costas, 2x. Habilidade: Passo sombrio (avança e fica invisível).",
		"hp": 140.0, "speed": 6.5, "armor": 0.0,
		"spell_power": 0.7, "special_cooldown": 1.5,
		"weapon": {"damage": 14.0, "cooldown": 0.3, "range": 1.9, "angle": 0.8, "push": 1.5,
			"element_scale": 1.0, "charges": 3},
		"backstab": 2.0,
		"ability": "shadow_step", "ability_label": "Passo sombrio", "ability_cooldown": 8.0,
	},
	"fighter": {
		"label": "Lutador",
		"description": "Muita vida e armadura. Golpes pesados e largos que empurram. Habilidade: Investida (atropela levando os elementos da fila).",
		"hp": 320.0, "speed": 4.5, "armor": 0.25,
		"spell_power": 0.8, "special_cooldown": 1.5,
		"weapon": {"damage": 35.0, "cooldown": 0.9, "range": 2.7, "angle": 1.3, "push": 8.0,
			"element_scale": 1.2, "charges": 1},
		"backstab": 1.0,
		"ability": "charge", "ability_label": "Investida", "ability_cooldown": 7.0,
	},
}


# Dados da classe; id desconhecido vira Mago.
static func info(id: String) -> Dictionary:
	return CLASSES.get(id, CLASSES[DEFAULT])


static func is_valid(id: String) -> bool:
	return CLASSES.has(id)
