# Times e quem pode afetar quem.
# - Arena (cooperativo): fogo amigo ligado; jogadores no time 0, inimigos no 1.
# - MOBA: sem fogo amigo; em aliados só a Vida (cura) tem efeito.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

const NEUTRAL := -1   # monstros da selva: hostis a todos
const BLUE := 0
const RED := 1
const TEAM_NAMES := {BLUE: "Azul", RED: "Vermelho", NEUTRAL: "Neutro"}
const TEAM_COLORS := {BLUE: Color(0.3, 0.5, 1.0), RED: Color(1.0, 0.3, 0.3), NEUTRAL: Color(0.7, 0.7, 0.5)}

static var friendly_fire := true


static func team_of(node: Object) -> int:
	var team = node.get("team")
	return NEUTRAL if team == null else team


static func is_hostile(team_a: int, team_b: int) -> bool:
	return team_a != team_b


# O time `source_team` pode causar dano/empurrar `target`?
static func can_harm(source_team: int, target: Object) -> bool:
	return friendly_fire or is_hostile(source_team, team_of(target))


# Elementos de um ataque do time `source_team` que valem contra `target`.
static func filter_elements(source_team: int, target: Object, elements: Array) -> Array:
	if can_harm(source_team, target):
		return elements
	return elements.filter(func(element): return element == E.Type.LIFE)
