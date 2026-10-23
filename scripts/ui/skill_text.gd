# Texto de uma skill com uma carga: o que ela faz e o que a carga muda nela.
# Usado na dica dos ícones do HUD e no Grimório de combos.
extends RefCounted

const ElementInfo = preload("res://scripts/core/element_info.gd")
const Ultimates = preload("res://scripts/core/ultimates.gd")
const Projectile = preload("res://scripts/gameplay/projectile.gd")


# Linhas da descrição (a primeira é o cabeçalho com tecla, mana e recarga).
static func lines(skill: Dictionary, charge: Array, key_text: String) -> PackedStringArray:
	var result := PackedStringArray(["%s (%s) — %d de mana, recarga de %d s" % [
		skill.label, key_text, roundi(skill.cost), roundi(skill.cooldown)],
		skill.get("description", "")])
	match skill.id:
		"orb":
			if not charge.is_empty():
				result.append("Com a carga: explode em área de %.1f m (%s)." % [
					Projectile.splash_radius_for(charge), ElementInfo.names(charge)])
		"mini_meteor":
			if not charge.is_empty():
				result.append("Zona: " + ElementInfo.describe(ElementInfo.ZONES, charge))
		"bless_curse":
			if not charge.is_empty():
				result.append("Carga: " + ElementInfo.names(charge))
				result.append("Bolha (segurar): " + ElementInfo.describe(ElementInfo.BUBBLE, charge))
		"ultimate":
			var id := Ultimates.resolve(charge)
			if id.is_empty():
				result.append("Carregue elementos (3 iguais = MEGA).")
			else:
				result.append("%s%s: %s" % ["MEGA " if Ultimates.is_mega(charge) else "", Ultimates.label(id),
					Ultimates.ULTIMATES[id].description])
				var zones := Ultimates.zone_elements(charge)
				if not zones.is_empty():
					result.append("Zonas: " + ElementInfo.describe(ElementInfo.ZONES, zones))
		_:
			if not charge.is_empty():
				result.append("Carga: " + ElementInfo.describe(ElementInfo.EFFECTS, charge))
	return result
