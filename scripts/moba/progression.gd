# MOBA: ouro, experiência, níveis, itens da loja e bônus. Lógica pura (testável).
# Todos os números são nossos e podem ser ajustados livremente.
extends RefCounted

const MAX_LEVEL := 12
const PASSIVE_GOLD := 2.0          # ouro por segundo para cada campeão
const START_GOLD := 300
const REWARD_RANGE := 14.0         # quem está perto quando algo morre ganha ouro/xp
const CHAMPION_KILL_GOLD := 150
const CHAMPION_KILL_XP_PER_LEVEL := 60
const TOWER_GOLD := 120            # para todo o time
const INHIBITOR_GOLD := 80
const MAX_ITEMS := 6
const SHOP_EXTRA_RANGE := 3.0      # pode comprar até um pouco fora da fonte

const ITEMS := {
	"amuleto": {"label": "Amuleto de vida", "cost": 300, "hp": 90.0, "description": "+90 de vida"},
	"foco": {"label": "Foco elemental", "cost": 350, "power": 0.12, "description": "+12% de dano"},
	"botas": {"label": "Botas velozes", "cost": 250, "speed": 0.8, "description": "+0,8 de velocidade"},
	"ampulheta": {"label": "Ampulheta", "cost": 400, "cooldown": 0.15, "mana": 40.0, "description": "-15% nas recargas, +40 de mana"},
	"couraca": {"label": "Couraça", "cost": 350, "armor": 0.1, "description": "+10% de armadura"},
}
const ITEM_ORDER := ["amuleto", "foco", "botas", "ampulheta", "couraca"]

const BUFFS := {
	"golem": {"label": "Fúria do Golem", "duration": 60.0, "power": 0.2},
	"guardiao": {"label": "Bênção do Guardião", "duration": 120.0, "power": 0.25, "speed": 0.5},
}


static func xp_to_next(level: int) -> int:
	return 80 + 40 * level


static func respawn_time(level: int) -> float:
	return 5.0 + 1.5 * level


# Soma xp e devolve [nível, xp restante] (para em MAX_LEVEL).
static func apply_xp(level: int, xp: int, gained: int) -> Array:
	xp += gained
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	if level >= MAX_LEVEL:
		xp = 0
	return [level, xp]


# Atributos finais do campeão: classe + nível + itens + bônus ativos.
static func stats(class_info: Dictionary, level: int, items: Array, buffs: Dictionary) -> Dictionary:
	var result := {
		"max_hp": class_info.hp * (1.0 + 0.08 * (level - 1)),
		"max_mana": class_info.mana * (1.0 + 0.08 * (level - 1)),
		"power": 1.0 + 0.06 * (level - 1),
		"speed": 0.0,
		"armor": class_info.armor,
		"cooldown": 1.0,
	}
	var power_bonus := 0.0
	for id in items:
		var item: Dictionary = ITEMS.get(id, {})
		result.max_hp += item.get("hp", 0.0)
		result.max_mana += item.get("mana", 0.0)
		power_bonus += item.get("power", 0.0)
		result.speed += item.get("speed", 0.0)
		result.armor += item.get("armor", 0.0)
		result.cooldown -= item.get("cooldown", 0.0)
	for id in buffs:
		var buff: Dictionary = BUFFS.get(id, {})
		power_bonus += buff.get("power", 0.0)
		result.speed += buff.get("speed", 0.0)
	result.power *= 1.0 + power_bonus
	result.armor = minf(result.armor, 0.6)
	result.cooldown = maxf(result.cooldown, 0.5)
	return result


# Motivo para não poder comprar, ou "" se pode.
static func cannot_buy(item_id: String, gold: int, items: Array, at_shop: bool) -> String:
	if not ITEMS.has(item_id):
		return "item desconhecido"
	if not at_shop:
		return "volte à fonte da base para comprar"
	if items.size() >= MAX_ITEMS:
		return "inventário cheio"
	if gold < ITEMS[item_id].cost:
		return "ouro insuficiente"
	return ""
