# IA de um campeão bot no MOBA (roda só no host, como filho do personagem).
# Usa os mesmos pedidos que um jogador (request_element, request_weapon...):
# - segue a rota atrás das próprias tropas;
# - luta com o que estiver perto, sem entrar sozinho no alcance de torres inimigas;
# - com pouca vida volta à base, se cura e compra itens.
extends Node

const E = preload("res://scripts/core/elements.gd")
const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")
const Progression = preload("res://scripts/moba/progression.gd")
const Specials = preload("res://scripts/core/specials.gd")
const Structure = preload("res://scripts/moba/structure.gd")

const THINK_TIME := 0.25
const SIGHT := 11.0
const RETREAT_HP := 0.3
const RESUME_HP := 0.9
const MAGE_DISTANCE := 6.5
const MELEE_DISTANCE := 1.4
const COMBO_PAUSE := 2.6        # espera entre combinações (1 s de disparo + duração)
const FOLLOW_BEHIND := 3.0      # distância atrás da tropa aliada mais avançada
const ITEM_PREFERENCE := {
	"mage": ["foco", "ampulheta", "amuleto", "botas", "foco", "couraca"],
	"assassin": ["foco", "botas", "foco", "amuleto", "ampulheta", "couraca"],
	"fighter": ["amuleto", "couraca", "botas", "foco", "amuleto", "ampulheta"],
}

var bot: Node
var lane := "norte"
var retreating := false
var _think := 0.0
var _combo_wait := 0.0


func _ready() -> void:
	bot = get_parent()
	lane = MobaMap.LANES[bot.color_index % 2]


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_think -= delta
	_combo_wait -= delta
	if _think > 0.0:
		return
	_think = THINK_TIME
	if bot.health.dead:
		retreating = false
		return
	var state = bot.get_parent().get("game_state")
	if state == null or state.is_over():
		bot.has_move_target = false
		return

	var hp_ratio: float = bot.health.hp / bot.health.max_hp
	if hp_ratio < RETREAT_HP:
		retreating = true
	if retreating:
		if hp_ratio >= RESUME_HP and bot.is_at_shop():
			retreating = false
		else:
			_go(MobaMap.fountain(bot.team))
			_maybe_buy()
			return
	_maybe_buy()

	var target := _pick_target()
	if target == null:
		_advance()
	else:
		_fight(target)


# --- Decisões ----------------------------------------------------------------

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("damageable"):
		if node == bot or node.is_queued_for_deletion() or node.health.dead:
			continue
		var other := Combat.team_of(node)
		if other == Combat.NEUTRAL or not Combat.is_hostile(bot.team, other):
			continue
		if node.get("invisible") != null and node.invisible > 0.0:
			continue
		var distance: float = bot.global_position.distance_to(node.global_position)
		if distance > SIGHT:
			continue
		var score := distance
		if node.is_in_group("structures"):
			if node.health.invulnerable or not _has_minions_near(node.global_position, Structure.TOWER_RANGE):
				continue
			score += 4.0
		elif node.is_in_group("players"):
			score -= 3.0 * (1.0 - node.health.hp / node.health.max_hp) + 1.0
		if _unsafe(node.global_position) and not node.is_in_group("structures"):
			continue
		if score < best_score:
			best_score = score
			best = node
	return best


func _fight(target: Node3D) -> void:
	var offset: Vector3 = target.global_position - bot.global_position
	offset.y = 0.0
	var distance := offset.length()
	var direction: Vector3 = offset.normalized() if distance > 0.01 else -bot.global_transform.basis.z
	var desired := MAGE_DISTANCE if bot.class_id == "mage" else MELEE_DISTANCE
	if target.is_in_group("structures"):
		desired += target.info.radius
	bot.aim_point = target.global_position

	if distance > desired + 0.5:
		bot.set_move_target(target.global_position - direction * desired)
	elif bot.class_id == "mage" and distance < desired - 2.5 and not target.is_in_group("structures"):
		# Mago: mantém distância.
		bot.set_move_target(bot.global_position - direction * 3.0)
	else:
		bot.has_move_target = false

	# Golpe (classes corpo a corpo), às vezes com um elemento na arma.
	if bot.class_id != "mage" and distance <= bot.cls.weapon.range + 0.3 and bot.weapon_timer <= 0.0:
		if bot.queue.is_empty() and randf() < 0.35:
			bot.request_element([E.Type.FIRE, E.Type.COLD, E.Type.LIGHTNING].pick_random())
		bot.request_weapon(direction)

	_maybe_ability(target, distance, direction)
	_maybe_special(target, distance)

	# Combinação de elementos (sai sozinha 1 s depois).
	if _combo_wait <= 0.0 and bot.queue.is_empty() and not bot._is_channeling() and distance <= 9.0:
		for element in _choose_combo(target, distance):
			bot.request_element(element)
		_combo_wait = COMBO_PAUSE


func _choose_combo(target: Node3D, distance: float) -> Array:
	if target.is_in_group("structures"):
		return [E.Type.EARTH, E.Type.EARTH]
	if distance <= 4.5:
		return [[E.Type.FIRE, E.Type.FIRE, E.Type.FIRE], [E.Type.COLD, E.Type.COLD], [E.Type.LIGHTNING, E.Type.LIGHTNING]].pick_random()
	return [[E.Type.EARTH, E.Type.EARTH], [E.Type.ARCANE, E.Type.FIRE], [E.Type.LIGHTNING, E.Type.LIGHTNING],
		[E.Type.EARTH, E.Type.FIRE]].pick_random()


func _maybe_ability(target: Node3D, distance: float, direction: Vector3) -> void:
	if bot.ability_cooldown > 0.0 or target.is_in_group("structures"):
		return
	if bot.class_id == "fighter" and distance >= 3.0 and distance <= 7.0:
		bot.request_ability(direction)
	elif bot.class_id == "assassin" and target.is_in_group("players") and distance >= 3.0 and distance <= 6.0:
		bot.request_ability(direction)
	elif bot.class_id == "mage" and distance <= 4.0 and bot.health.hp < bot.health.max_hp * 0.5:
		bot.request_ability(direction)


# Meteoro de vez em quando num campeão inimigo.
func _maybe_special(target: Node3D, distance: float) -> void:
	if not target.is_in_group("players") or distance > 12.0 or bot.special_cooldowns.has("meteor"):
		return
	if not bot.queue.is_empty() or randf() > 0.15:
		return
	for element in Specials.SPECIALS.meteor.recipe:
		bot.request_element(element)
	bot.request_special(target.global_position)


# Sem alvo: segue a rota, atrás da tropa aliada mais avançada (ou na própria torre).
func _advance() -> void:
	var path := MobaMap.lane_path(bot.team, lane)
	var front: Node3D = null
	var best_progress := -INF
	for minion in get_tree().get_nodes_in_group("minions"):
		if minion.team != bot.team or minion.is_queued_for_deletion() or minion.path.is_empty():
			continue
		if signf(minion.path[3].z) != MobaMap.lane_sign(lane):
			continue
		var progress: float = minion.waypoint * 1000.0 - minion.global_position.distance_to(path[mini(minion.waypoint, path.size() - 1)])
		if progress > best_progress:
			best_progress = progress
			front = minion
	if front != null:
		var back: Vector3 = path[0] - front.global_position
		back.y = 0.0
		_go(front.global_position + back.normalized() * FOLLOW_BEHIND)
		return
	_go(_own_front_tower())


func _own_front_tower() -> Vector3:
	var main := bot.get_parent()
	var key: String = MobaMap.TEAM_KEYS[bot.team]
	for suffix in ["torre_externa", "torre_interna"]:
		var tower = main.get_node_or_null("%s_%s_%s" % [key, lane, suffix])
		if tower != null and not tower.health.dead:
			var toward_enemy := Vector3(-MobaMap.side(bot.team), 0, 0)
			return tower.global_position + toward_enemy * 3.0
	return MobaMap.fountain(bot.team)


func _maybe_buy() -> void:
	if not bot.is_at_shop():
		return
	var wishlist: Array = ITEM_PREFERENCE.get(bot.class_id, Progression.ITEM_ORDER)
	if bot.items.size() >= wishlist.size():
		return
	var next_item: String = wishlist[bot.items.size()]
	if Progression.cannot_buy(next_item, bot.gold, bot.items, true).is_empty():
		bot.request_buy(next_item)


# --- Utilidades --------------------------------------------------------------

func _go(point: Vector3) -> void:
	if bot.global_position.distance_to(point) > 0.6:
		bot.set_move_target(point)


func _has_minions_near(point: Vector3, radius: float) -> bool:
	for minion in get_tree().get_nodes_in_group("minions"):
		if minion.team == bot.team and minion.global_position.distance_to(point) <= radius:
			return true
	return false


# Ponto dentro do alcance de uma torre inimiga viva sem tropas aliadas segurando o tiro.
func _unsafe(point: Vector3) -> bool:
	for structure in get_tree().get_nodes_in_group("structures"):
		if structure.kind != "tower" or structure.health.dead or not Combat.is_hostile(bot.team, structure.team):
			continue
		if structure.global_position.distance_to(point) <= Structure.TOWER_RANGE + 1.0 \
				and not _has_minions_near(structure.global_position, Structure.TOWER_RANGE):
			return true
	return false
