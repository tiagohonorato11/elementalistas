# Missões do modo Mundo: uma corrente em ordem, dada pela Anciã da vila.
# Uma missão de cada vez: aceitar, derrotar os monstros pedidos (contam os que
# morrerem perto de você) e voltar à Anciã para entregar e receber a recompensa.
# O progresso de cada personagem é um dicionário: id -> {"count": n, "done": bool}.
# Lógica pura, para ser testável. Os números são nossos e podem ser ajustados.
extends RefCounted

const QUESTS := [
	{"id": "carnicais", "title": "Carniçais nos campos", "kinds": ["ghoul"], "count": 5,
		"gold": 120, "xp": 150,
		"offer": "Os Carniçais saíram dos campos a oeste e rondam a estrada. Derrote 5 deles.",
		"done": "Os campos estão mais calmos. Tome, você mereceu."},
	{"id": "ossos", "title": "Ossos inquietos", "kinds": ["skeleton", "skeleton_archer"], "count": 6,
		"gold": 160, "xp": 220,
		"offer": "Os mortos do cemitério a leste se levantaram. Derrube 6 esqueletos.",
		"done": "Que os ossos voltem a descansar. Obrigada."},
	{"id": "golem", "title": "O Golem do bosque", "kinds": ["forest_golem"], "count": 1,
		"gold": 220, "xp": 320,
		"offer": "Um Golem guarda o bosque a noroeste e não deixa ninguém colher lenha. Derrote-o.",
		"done": "O bosque é nosso de novo. Você está ficando forte."},
	{"id": "guardiao", "title": "O Guardião do covil", "kinds": ["world_boss"], "count": 1,
		"gold": 450, "xp": 600,
		"offer": "Tudo isso vem do covil ao norte, onde dorme o Guardião. Leve seus amigos e acabe com ele.",
		"done": "Você salvou a vila! Por enquanto... dizem que há mais terras além das montanhas."},
]


static func info(id: String) -> Dictionary:
	for quest in QUESTS:
		if quest.id == id:
			return quest
	return {}


# Missão aceita e ainda não entregue ("" se nenhuma).
static func active(progress: Dictionary) -> String:
	for quest in QUESTS:
		var entry: Dictionary = progress.get(quest.id, {})
		if not entry.is_empty() and not entry.get("done", false):
			return quest.id
	return ""


# Próxima missão que a Anciã oferece ("" se há uma ativa ou se acabaram).
static func next_offer(progress: Dictionary) -> String:
	if not active(progress).is_empty():
		return ""
	for quest in QUESTS:
		if not progress.has(quest.id):
			return quest.id
	return ""


static func is_complete(progress: Dictionary, id: String) -> bool:
	var entry: Dictionary = progress.get(id, {})
	return not entry.is_empty() and not entry.get("done", false) and entry.get("count", 0) >= info(id).get("count", 1)


static func accept(progress: Dictionary, id: String) -> Dictionary:
	var result := progress.duplicate(true)
	if next_offer(progress) == id:
		result[id] = {"count": 0, "done": false}
	return result


# Um monstro do tipo `kind` caiu perto do personagem.
static func on_kill(progress: Dictionary, kind: String) -> Dictionary:
	var id := active(progress)
	if id.is_empty() or not (kind in info(id).kinds):
		return progress
	var result := progress.duplicate(true)
	result[id]["count"] = mini(result[id]["count"] + 1, info(id).count)
	return result


static func turn_in(progress: Dictionary, id: String) -> Dictionary:
	var result := progress.duplicate(true)
	if is_complete(progress, id):
		result[id]["done"] = true
	return result


# Texto curto para o HUD: "Carniçais nos campos (3/5)".
static func tracker(progress: Dictionary) -> String:
	var id := active(progress)
	if id.is_empty():
		return "fale com a Anciã na vila" if not next_offer(progress).is_empty() else "todas as missões feitas"
	var quest := info(id)
	var count: int = progress[id].count
	if count >= quest.count:
		return "%s: volte à Anciã" % quest.title
	return "%s (%d/%d)" % [quest.title, count, quest.count]
