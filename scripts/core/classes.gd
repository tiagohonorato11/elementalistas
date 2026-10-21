# Classes jogáveis. Cada uma tem atributos, golpe básico (botão esquerdo), mana
# e 4 skills em Q W E R. As skills usam a carga de elementos (D F G) do jogador.
# Todos os números são nossos e podem ser ajustados.
extends RefCounted

const DEFAULT := "mage"
const ORDER := ["mage", "assassin", "fighter"]
const SLOTS := ["q", "w", "e", "r"]

# Em toda skill: label, cost (mana), cooldown (s) e os números próprios dela.
# W é dupla: aliado/si mesmo (ally) ou inimigo sob o mouse (enemy).
const CLASSES := {
	"mage": {
		"label": "Mago",
		"description": "Q Orbe | W Bênção (aliado) ou Maldição (inimigo) | E Raio laser | R Ultimate. Muita mana.",
		"hp": 200.0, "speed": 5.0, "armor": 0.0,
		"mana": 160.0, "mana_regen": 5.0,
		"spell_power": 1.0,
		"weapon": {"damage": 20.0, "cooldown": 0.6, "range": 2.3, "angle": 1.05, "push": 4.0},
		"backstab": 1.0,
		"skills": {
			"q": {"id": "orb", "label": "Orbe", "cost": 15.0, "cooldown": 1.5,
				"damage": 30.0, "speed": 20.0},
			"w": {"id": "bless_curse", "label": "Bênção/Maldição", "cost": 30.0, "cooldown": 8.0,
				"heal": 30.0, "slow": 0.4, "vulnerable": 0.2, "duration": 4.0},
			"e": {"id": "laser", "label": "Raio laser", "cost": 35.0, "cooldown": 6.0,
				"dps": 35.0, "duration": 1.5, "range": 20.0},
			"r": {"id": "ultimate", "label": "Ultimate", "cost": 80.0, "cooldown": 60.0, "power": 1.0},
		},
	},
	"assassin": {
		"label": "Assassino",
		"description": "Q Adaga (2x pelas costas) | W Véu (aliado: invisível) ou Marca (inimigo) | E Passo sombrio | R Ultimate. Rápido e frágil.",
		"hp": 140.0, "speed": 6.5, "armor": 0.0,
		"mana": 110.0, "mana_regen": 6.0,
		"spell_power": 0.8,
		"weapon": {"damage": 14.0, "cooldown": 0.3, "range": 1.9, "angle": 0.8, "push": 1.5},
		"backstab": 2.0,
		"skills": {
			"q": {"id": "dagger", "label": "Adaga", "cost": 12.0, "cooldown": 2.0,
				"damage": 24.0, "speed": 30.0},
			"w": {"id": "veil_mark", "label": "Véu/Marca", "cost": 25.0, "cooldown": 10.0,
				"invisible": 2.5, "vulnerable": 0.3, "duration": 4.0},
			"e": {"id": "shadow_step", "label": "Passo sombrio", "cost": 25.0, "cooldown": 8.0,
				"distance": 6.0, "radius": 2.5, "damage": 25.0},
			"r": {"id": "ultimate", "label": "Ultimate", "cost": 70.0, "cooldown": 60.0, "power": 0.8},
		},
	},
	"fighter": {
		"label": "Lutador",
		"description": "Q Golpe giratório | W Grito (aliado) ou Desafio (inimigo) | E Investida | R Ultimate. Muita vida e armadura.",
		"hp": 320.0, "speed": 4.5, "armor": 0.25,
		"mana": 100.0, "mana_regen": 4.0,
		"spell_power": 0.8,
		"weapon": {"damage": 35.0, "cooldown": 0.9, "range": 2.7, "angle": 1.3, "push": 8.0},
		"backstab": 1.0,
		"skills": {
			"q": {"id": "whirl", "label": "Golpe giratório", "cost": 15.0, "cooldown": 4.0,
				"damage": 35.0, "radius": 2.8, "push": 7.0},
			"w": {"id": "shout", "label": "Grito/Desafio", "cost": 25.0, "cooldown": 10.0,
				"heal": 20.0, "haste": 0.3, "fortify": 0.3, "slow": 0.4, "duration": 4.0},
			"e": {"id": "charge", "label": "Investida", "cost": 25.0, "cooldown": 7.0,
				"damage": 30.0, "push": 10.0},
			"r": {"id": "ultimate", "label": "Ultimate", "cost": 60.0, "cooldown": 60.0, "power": 0.8},
		},
	},
}


# Dados da classe; id desconhecido vira Mago.
static func info(id: String) -> Dictionary:
	return CLASSES.get(id, CLASSES[DEFAULT])


static func is_valid(id: String) -> bool:
	return CLASSES.has(id)


static func skill(id: String, slot: String) -> Dictionary:
	return info(id).skills.get(slot, {})
