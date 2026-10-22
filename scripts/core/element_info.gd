# Textos curtos sobre os elementos, para as dicas do HUD e a tela de ajuda (F1).
# Só texto: os números de verdade ficam em elements.gd, health.gd, zone.gd e player.gd.
extends RefCounted

const E = preload("res://scripts/core/elements.gd")

# O que o elemento faz ao acertar.
const EFFECTS := {
	E.Type.WATER: "molha (Raio causa o dobro) e apaga fogo",
	E.Type.LIFE: "cura; levanta aliados caídos",
	E.Type.SHIELD: "barreiras e proteção",
	E.Type.COLD: "resfria (lento); em alvo molhado, congela",
	E.Type.LIGHTNING: "dano alto; dobrado em alvo molhado",
	E.Type.ARCANE: "dano alto",
	E.Type.EARTH: "dano alto e empurra; estilhaça congelados (2x)",
	E.Type.FIRE: "incendeia (dano por segundo)",
	E.Type.STEAM: "Água + Fogo: escalda e molha",
	E.Type.ICE: "Água + Frio: cristal que resfria",
	E.Type.VOID: "desfaz escudos, barreiras e bônus; drena mana",
	E.Type.GRAVITY: "puxa o alvo para você e o deixa pesado",
	E.Type.SMOKE: "cega por 3 s (Água tira)",
	E.Type.BLOOD: "sangramento; em você, roubo de vida; nas skills, rouba 25% do dano",
}

# Zona que o elemento deixa (Mini meteoro e elementos secundários do ultimate).
const ZONES := {
	E.Type.GRAVITY: "magnetismo: puxa para o centro",
	E.Type.FIRE: "chão em brasa: queima",
	E.Type.COLD: "lento; quem fica 2,5 s congela",
	E.Type.ICE: "estilhaços ao cair",
	E.Type.LIGHTNING: "campo elétrico: raios a cada 0,5 s",
	E.Type.WATER: "onda que molha e empurra",
	E.Type.STEAM: "nuvem escaldante",
	E.Type.EARTH: "cratera: atordoa ao cair",
	E.Type.ARCANE: "explode de novo depois de 1,5 s",
	E.Type.LIFE: "fonte que cura aliados",
	E.Type.SHIELD: "domo: aliados levam metade do dano",
	E.Type.VOID: "drena mana e tira proteções",
	E.Type.SMOKE: "nuvem que cega e esconde aliados",
	E.Type.BLOOD: "poça: sangramento e roubo de vida",
}

# Poder que o elemento dá à bolha de escudo do Mago (W segurado).
const BUBBLE := {
	E.Type.FIRE: "queima quem está dentro",
	E.Type.COLD: "resfria quem está dentro",
	E.Type.LIGHTNING: "dá choque em quem está dentro",
	E.Type.STEAM: "escalda quem está dentro",
	E.Type.ICE: "resfria quem está dentro",
	E.Type.WATER: "limpa queimadura, cegueira e sangramento",
	E.Type.LIFE: "cura os aliados dentro",
	E.Type.EARTH: "barreira mais forte",
	E.Type.SHIELD: "dura o dobro e apaga projéteis",
	E.Type.ARCANE: "reflete projéteis",
	E.Type.VOID: "apaga projéteis inimigos",
	E.Type.GRAVITY: "empurra inimigos para fora",
	E.Type.SMOKE: "esconde os aliados dentro",
	E.Type.BLOOD: "aliados dentro roubam vida",
}


static func names(elements: Array) -> String:
	var result := PackedStringArray()
	for element in elements:
		result.append(E.NAMES[element])
	return ", ".join(result)


# "Fogo: chão em brasa: queima; Gravidade: magnetismo..." (sem repetir elementos).
static func describe(table: Dictionary, elements: Array) -> String:
	var seen: Array = []
	var parts := PackedStringArray()
	for element in elements:
		if element in seen or not table.has(element):
			continue
		seen.append(element)
		parts.append("%s: %s" % [E.NAMES[element], table[element]])
	return "; ".join(parts)
