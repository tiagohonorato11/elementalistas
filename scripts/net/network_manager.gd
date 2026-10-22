# Rede (autoload "Network"): hospedar/entrar, lista de jogadores, início da partida
# e descoberta automática de partidas no mesmo Wi-Fi (broadcast UDP).
extends Node

const Classes = preload("res://scripts/core/classes.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Combat = preload("res://scripts/core/combat.gd")

signal players_changed
signal connected
signal connection_failed
signal all_loaded
signal player_left(peer_id: int)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 6
const MOBA_TEAM_SIZE := 3   # com bots ligados, cada time é completado até 3
const MODES := {"arena": "Arena (ondas)", "moba": "MOBA (3v3)", "practice": "Treino", "world": "Mundo (RPG)"}
const DISCOVERY_TAG := "ELEMENTISTAS"
const DISCOVERY_TIMEOUT_MS := 3000
const GAME_SCENE := "res://scenes/main.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SETTINGS_PATH := "user://settings.cfg"

var players: Array = []          # ids dos peers na partida (o host é sempre 1)
var classes := {}                # id do peer -> classe escolhida (decidido pelo host)
var loadouts := {}               # id do peer -> 3 elementos escolhidos (D F G)
var teams := {}                  # id do peer -> time no MOBA (decidido pelo host)
var settings := {"mode": "arena", "bots": true}   # escolhidos pelo host
var my_class := Classes.DEFAULT  # classe escolhida neste PC (salva entre sessões)
var my_loadouts := {}            # classe -> 3 elementos escolhidos neste PC (salvos)
var in_game := false
var last_message := ""           # mostrado no lobby ao voltar para ele
var found_games := {}            # ip -> {"players": int, "seen": int}
var command_line_used := false

var _loaded_peers: Array = []
var _all_loaded_sent := false
var _broadcaster: PacketPeerUDP
var _broadcast_targets := PackedStringArray()
var _broadcast_timer := 0.0
var _listener: PacketPeerUDP


func _ready() -> void:
	_load_class()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): _fail_connection.call_deferred())
	multiplayer.server_disconnected.connect(
		func(): back_to_lobby.call_deferred("O host encerrou a partida."))


func is_online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


# --- Conexão -----------------------------------------------------------------

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	players = [1]
	classes = {1: my_class}
	loadouts = {1: my_elements()}
	teams = {1: Combat.BLUE}
	in_game = false
	_start_broadcast()
	players_changed.emit()
	return OK


func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	_stop_broadcast()
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = []
	classes = {}
	loadouts = {}
	teams = {}
	in_game = false
	_loaded_peers = []
	_all_loaded_sent = false
	players_changed.emit()


func back_to_lobby(message: String) -> void:
	leave()
	last_message = message
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _fail_connection() -> void:
	leave()
	connection_failed.emit()


func _on_connected_to_server() -> void:
	_report_class.rpc_id(1, my_class, my_elements())
	connected.emit()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.append(id)
	classes[id] = Classes.DEFAULT   # até o jogador informar a classe dele
	loadouts[id] = Loadout.default_for(Classes.DEFAULT)
	teams[id] = _smaller_team()
	_broadcast_lobby()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	classes.erase(id)
	loadouts.erase(id)
	teams.erase(id)
	_loaded_peers.erase(id)
	_broadcast_lobby()
	player_left.emit(id)
	if in_game:
		_check_all_loaded()


func _broadcast_lobby() -> void:
	_sync_players.rpc(players, classes, loadouts, teams, settings)


@rpc("authority", "call_local", "reliable")
func _sync_players(list: Array, class_map: Dictionary, loadout_map: Dictionary, team_map: Dictionary,
		game_settings: Dictionary) -> void:
	players = list.duplicate()
	classes = class_map.duplicate()
	loadouts = loadout_map.duplicate()
	teams = team_map.duplicate()
	settings = game_settings.duplicate()
	players_changed.emit()


# --- Modo de jogo e times ----------------------------------------------------

func game_mode() -> String:
	return settings.get("mode", "arena")


# Só o host muda o modo e os bots; todos recebem pela sincronização do lobby.
func set_setting(key: String, value) -> void:
	if not multiplayer.is_server():
		return
	settings[key] = value
	if is_online():
		_broadcast_lobby()


func team_of(peer_id: int) -> int:
	return teams.get(peer_id, Combat.BLUE)


func set_my_team(team: int) -> void:
	if is_online() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_report_team.rpc_id(1, team)


@rpc("any_peer", "call_local", "reliable")
func _report_team(team: int) -> void:
	if not multiplayer.is_server() or not (team in [Combat.BLUE, Combat.RED]):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender in players and _team_size(team) < MOBA_TEAM_SIZE:
		teams[sender] = team
		_broadcast_lobby()


func _team_size(team: int) -> int:
	return players.filter(func(peer): return team_of(peer) == team).size()


func _smaller_team() -> int:
	return Combat.BLUE if _team_size(Combat.BLUE) <= _team_size(Combat.RED) else Combat.RED


# Bots que completam os times no MOBA: [{"team": 0, "class": "mage", "elements": [...]}, ...].
func bot_plan() -> Array:
	var plan := []
	if game_mode() != "moba" or not settings.get("bots", true):
		return plan
	for team in [Combat.BLUE, Combat.RED]:
		for i in maxi(MOBA_TEAM_SIZE - _team_size(team), 0):
			plan.append({"team": team, "class": Classes.ORDER.pick_random(), "elements": Loadout.random()})
	return plan


# --- Classes e elementos ----------------------------------------------------------

func class_of(peer_id: int) -> String:
	return classes.get(peer_id, Classes.DEFAULT)


func elements_of(peer_id: int) -> Array:
	return Loadout.sanitize(loadouts.get(peer_id, []), class_of(peer_id))


# Os 3 elementos escolhidos neste PC para a classe atual (padrão da classe se nada salvo).
func my_elements() -> Array:
	return Loadout.sanitize(my_loadouts.get(my_class, []), my_class)


# Escolha de elementos no lobby (precisa ser válida: 3, diferentes, sem opostos).
func set_my_elements(elements: Array) -> void:
	if not Loadout.is_valid(elements):
		return
	my_loadouts[my_class] = elements.duplicate()
	_save_class()
	_report_choice()


# Escolha feita no lobby; vale a partir da próxima partida (ou reinício).
func set_my_class(id: String) -> void:
	if not Classes.is_valid(id):
		return
	my_class = id
	_save_class()
	_report_choice()


func _report_choice() -> void:
	if is_online() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_report_class.rpc_id(1, my_class, my_elements())


@rpc("any_peer", "call_local", "reliable")
func _report_class(id: String, elements: Array) -> void:
	if not multiplayer.is_server() or not Classes.is_valid(id):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender in players:
		classes[sender] = id
		loadouts[sender] = Loadout.sanitize(elements, id)
		_broadcast_lobby()


func _load_class() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var saved: String = config.get_value("jogador", "classe", Classes.DEFAULT)
		if Classes.is_valid(saved):
			my_class = saved
		for id in Classes.ORDER:
			var elements = config.get_value("jogador", "elementos_" + id, [])
			if elements is Array and Loadout.is_valid(elements):
				my_loadouts[id] = elements


func _save_class() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("jogador", "classe", my_class)
	for id in my_loadouts:
		config.set_value("jogador", "elementos_" + id, my_loadouts[id])
	config.save(SETTINGS_PATH)


# --- Início da partida -------------------------------------------------------

func start_game() -> void:
	if not multiplayer.is_server():
		return
	in_game = true
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	_stop_broadcast()
	_start_game.rpc()


# Recarrega a arena para todos (mesmos jogadores).
func restart_game() -> void:
	if multiplayer.is_server() and in_game:
		_start_game.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	in_game = true
	_loaded_peers = []
	_all_loaded_sent = false
	stop_listening()
	get_tree().change_scene_to_file(GAME_SCENE)


# Cada peer avisa o host quando a cena do jogo terminou de carregar.
func report_loaded() -> void:
	_report_loaded.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _report_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not (id in _loaded_peers):
		_loaded_peers.append(id)
	_check_all_loaded()


func _check_all_loaded() -> void:
	if _all_loaded_sent:
		return
	for id in players:
		if not (id in _loaded_peers):
			return
	_all_loaded_sent = true
	all_loaded.emit()


# --- Descoberta na rede local ------------------------------------------------

# Endereços IPv4 privados desta máquina, com o nome do adaptador (ex.: "Wi-Fi").
func lan_addresses() -> Array:
	var result := []
	for iface in IP.get_local_interfaces():
		for ip in iface.addresses:
			if _is_private_ipv4(ip):
				result.append({"name": iface.friendly, "ip": ip})
	return result


static func _is_private_ipv4(ip: String) -> bool:
	if ":" in ip or not ip.is_valid_ip_address():
		return false
	if ip.begins_with("192.168.") or ip.begins_with("10."):
		return true
	if ip.begins_with("172."):
		var second := ip.split(".")[1].to_int()
		return second >= 16 and second <= 31
	return false


func start_listening() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	# Só um programa por PC consegue escutar; nas outras janelas use o IP manual.
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	found_games.clear()


func _start_broadcast() -> void:
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcast_targets = PackedStringArray(["255.255.255.255"])
	for entry in lan_addresses():
		var parts: PackedStringArray = entry.ip.split(".")
		_broadcast_targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	_broadcast_timer = 0.0


func _stop_broadcast() -> void:
	if _broadcaster != null:
		_broadcaster.close()
		_broadcaster = null


func _process(delta: float) -> void:
	if _broadcaster != null:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = 1.0
			var packet := ("%s|%d" % [DISCOVERY_TAG, players.size()]).to_utf8_buffer()
			for target in _broadcast_targets:
				_broadcaster.set_dest_address(target, DISCOVERY_PORT)
				_broadcaster.put_packet(packet)

	if _listener != null:
		while _listener.get_available_packet_count() > 0:
			var text := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parts := text.split("|")
			if parts.size() == 2 and parts[0] == DISCOVERY_TAG:
				found_games[ip] = {"players": parts[1].to_int(), "seen": Time.get_ticks_msec()}
		var now := Time.get_ticks_msec()
		for ip in found_games.keys():
			if now - found_games[ip].seen > DISCOVERY_TIMEOUT_MS:
				found_games.erase(ip)
