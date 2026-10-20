# Rede (autoload "Network"): hospedar/entrar, lista de jogadores, início da partida
# e descoberta automática de partidas no mesmo Wi-Fi (broadcast UDP).
extends Node

signal players_changed
signal connected
signal connection_failed
signal all_loaded
signal player_left(peer_id: int)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 4
const DISCOVERY_TAG := "ELEMENTISTAS"
const DISCOVERY_TIMEOUT_MS := 3000
const GAME_SCENE := "res://scenes/main.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"

var players: Array = []          # ids dos peers na partida (o host é sempre 1)
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
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected.emit())
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


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.append(id)
	_sync_players.rpc(players)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	_loaded_peers.erase(id)
	_sync_players.rpc(players)
	player_left.emit(id)
	if in_game:
		_check_all_loaded()


@rpc("authority", "call_local", "reliable")
func _sync_players(list: Array) -> void:
	players = list.duplicate()
	players_changed.emit()


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
