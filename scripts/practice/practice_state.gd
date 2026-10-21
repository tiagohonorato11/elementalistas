# Estado do modo Treino (arena de testes, como a ferramenta de treino de um MOBA).
# Sem ondas nem fim de partida. Guarda as opções de teste (sincronizadas pelo host)
# e atende os pedidos do painel (practice_panel.gd), venham do host ou dos amigos:
# - Mana infinita, Sem recarga, Imortal e Bonecos andam (opções ligáveis);
# - zerar recargas, encher vida e mana, limpar estados;
# - pôr e tirar bonecos, zerar o medidor de dano;
# - trocar de classe e de elementos na hora, sem voltar ao lobby.
# Quem cai sem Imortal volta em 3 s no mesmo lugar.
extends Node3D

const Classes = preload("res://scripts/core/classes.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const SyncUtil = preload("res://scripts/net/sync_util.gd")
const Dummy = preload("res://scripts/practice/dummy.gd")

const OPTIONS := {
	"infinite_mana": "Mana infinita",
	"no_cooldowns": "Sem recarga",
	"immortal": "Imortal",
	"dummies_move": "Bonecos andam",
}
const MAX_DUMMIES := 10
const REVIVE_TIME := 3.0
# Onde os bonecos aparecem (o primeiro lugar livre), à frente do ponto de partida.
const SPOTS := [Vector3(0, 0, -6), Vector3(-4, 0, -8), Vector3(4, 0, -8), Vector3(-8, 0, -3),
	Vector3(8, 0, -3), Vector3(-9, 0, -12), Vector3(9, 0, -12), Vector3(-4, 0, -13),
	Vector3(4, 0, -13), Vector3(-15, 0, -8)]
const START_DUMMIES := ["dummy", "armored", "fighter"]

var infinite_mana := false
var no_cooldowns := false
var immortal := false
var dummies_move := false
var main: Node
var _down := {}                 # personagem caído -> segundos para voltar


func _ready() -> void:
	main = get_parent()
	SyncUtil.add_sync(self, "StateSync", 1, [".:infinite_mana", ".:no_cooldowns", ".:immortal", ".:dummies_move"])


# Chamado pelo main no host quando todos carregaram.
func start() -> void:
	for kind in START_DUMMIES:
		_add_dummy(kind)


# Sem fim de partida (o main pergunta para liberar o R de jogar de novo).
func is_over() -> bool:
	return false


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for player in get_tree().get_nodes_in_group("players"):
		if player.is_queued_for_deletion():
			continue
		if infinite_mana:
			player.mana = player.max_mana
		if no_cooldowns and not player.skill_cooldowns.is_empty():
			player.skill_cooldowns = {}
		if immortal:
			if player.health.dead:
				player.health.revive()
			player.health.hp = player.health.max_hp
		elif player.health.dead:
			_down[player] = _down.get(player, REVIVE_TIME) - delta
			if _down[player] <= 0.0:
				_down.erase(player)
				player.health.revive()
				player.health.hp = player.health.max_hp


# --- Pedidos do painel ---------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_option(id: String, on: bool) -> void:
	if multiplayer.is_server() and OPTIONS.has(id):
		set(id, on)


@rpc("any_peer", "call_local", "reliable")
func request_action(action: String, arg: String) -> void:
	if not multiplayer.is_server():
		return
	var player: Node = _player_of(_sender())
	match action:
		"reset_cooldowns":
			if player != null:
				player.skill_cooldowns = {}
		"refill":
			if player != null:
				player.health.revive()
				player.health.hp = player.health.max_hp
				player.mana = player.max_mana
		"clear_status":
			if player != null:
				var hp: float = player.health.hp
				player.health.reset()
				player.health.hp = hp
				player.invisible = 0.0
		"add_dummy":
			if Dummy.KINDS.has(arg):
				_add_dummy(arg)
		"clear_dummies":
			for dummy in get_tree().get_nodes_in_group("dummies"):
				dummy.queue_free()
		"reset_meter":
			for dummy in get_tree().get_nodes_in_group("dummies"):
				dummy.reset_meter()


# Troca a classe e os elementos de quem pediu, no mesmo lugar (ver player.apply_loadout).
@rpc("any_peer", "call_local", "reliable")
func request_loadout(class_id: String, elements: Array) -> void:
	if not multiplayer.is_server() or not Classes.is_valid(class_id) or not Loadout.is_valid(elements):
		return
	var peer := _sender()
	var player: Node = _player_of(peer)
	if player == null:
		return
	Network.classes[peer] = class_id
	Network.loadouts[peer] = elements.duplicate()
	player.apply_loadout.rpc(class_id, elements)


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if sender == 0 else sender


func _player_of(peer: int) -> Node:
	return main.get_node_or_null("Player%d" % peer)


func _add_dummy(kind: String) -> void:
	var dummies := get_tree().get_nodes_in_group("dummies").filter(func(node): return not node.is_queued_for_deletion())
	if dummies.size() >= MAX_DUMMIES:
		return
	var spot: Vector3 = SPOTS[dummies.size() % SPOTS.size()]
	for candidate in SPOTS:
		if dummies.all(func(dummy): return dummy.home.distance_to(candidate) > 1.5):
			spot = candidate
			break
	main.spawn_entity({"type": "dummy", "kind": kind, "pos": spot})
