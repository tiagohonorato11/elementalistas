# Som e música (autoload "Audio"). Só toca: nada aqui afeta a lógica do jogo.
# - play(id, posição): efeito curto, com variação de arquivo e de tom;
# - make_loop(id, pai): som contínuo preso a um nó (feitiços, ambiente);
# - music(contexto): trilha com troca suave; em combate, a trilha esquenta.
# Volumes por canal (Música, Efeitos, Ambiente) ficam salvos em user://audio.cfg.
extends Node

const SFX := "res://assets/audio/sfx/"
const MUSIC := "res://assets/audio/music/"
const SETTINGS_PATH := "user://audio.cfg"
const BUSES := ["Music", "SFX", "Ambience"]
const BUS_LABELS := {"Music": "Música", "SFX": "Efeitos", "Ambience": "Ambiente"}
const DEFAULT_VOLUMES := {"Music": 0.6, "SFX": 0.8, "Ambience": 0.7}

const MAX_VOICES := 5          # cópias simultâneas do mesmo som
const MIN_GAP := 0.05          # segundos entre duas cópias do mesmo som
const COMBAT_HOLD := 9.0       # segundos sem luta até a trilha acalmar
const FADE := 1.8

# id -> [arquivos (k/ = Kenney, s/ = sintetizado), volume em dB, variação de tom]
const SOUNDS := {
	# Fila e feitiços
	"element_water": [["s/element_water"], -8.0, 0.0],
	"element_life": [["s/element_life"], -8.0, 0.0],
	"element_shield": [["s/element_shield"], -8.0, 0.0],
	"element_cold": [["s/element_cold"], -8.0, 0.0],
	"element_lightning": [["s/element_lightning"], -8.0, 0.0],
	"element_arcane": [["s/element_arcane"], -8.0, 0.0],
	"element_earth": [["s/element_earth"], -8.0, 0.0],
	"element_fire": [["s/element_fire"], -8.0, 0.0],
	"spray_fire": [["s/spray_fire"], -6.0, 0.0],
	"spray_water": [["s/spray_water"], -6.0, 0.0],
	"spray_cold": [["s/spray_cold"], -8.0, 0.0],
	"spray_steam": [["s/spray_steam"], -9.0, 0.0],
	"beam_arcane": [["s/beam_arcane"], -6.0, 0.0],
	"beam_life": [["s/beam_life"], -10.0, 0.0],
	"arc": [["s/arc_loop"], -7.0, 0.0],
	"charge": [["s/charge_loop"], -10.0, 0.0],
	"burning": [["s/spray_fire"], -18.0, 0.0],
	"launch": [["s/launch"], -4.0, 0.12],
	"bolt": [["s/bolt"], -2.0, 0.1],
	"heal": [["s/heal"], -6.0, 0.05],
	"whoosh": [["s/whoosh"], -6.0, 0.15],
	"shield_up": [["k/forceField_000", "k/forceField_001", "k/forceField_002"], -6.0, 0.08],
	"stone_up": [["k/impactMining_000", "k/impactMining_001", "k/impactMining_002"], -2.0, 0.1],
	"area": [["k/forceField_003", "k/forceField_004"], -4.0, 0.1],
	"slash": [["k/knifeSlice", "k/knifeSlice2", "k/drawKnife1", "k/drawKnife2"], -4.0, 0.12],
	"chop": [["k/chop"], -3.0, 0.1],
	# Impactos
	"impact_rock": [["k/impactMining_003", "k/impactMining_004", "k/impactWood_heavy_000"], -2.0, 0.1],
	"impact_ice": [["k/impactGlass_heavy_000", "k/impactGlass_heavy_001", "k/impactGlass_heavy_002"], -4.0, 0.1],
	"impact_magic": [["k/impactGeneric_light_000", "k/impactGeneric_light_001", "k/impactGeneric_light_002"], -2.0, 0.15],
	"explosion": [["k/lowFrequency_explosion_000", "k/lowFrequency_explosion_001"], 0.0, 0.08],
	"crunch": [["k/explosionCrunch_000", "k/explosionCrunch_001", "k/explosionCrunch_002"], -3.0, 0.1],
	"hit_flesh": [["k/impactPunch_medium_000", "k/impactPunch_medium_001", "k/impactPunch_medium_002", "k/impactPunch_medium_003"], -6.0, 0.12],
	"hit_bone": [["k/impactWood_medium_000", "k/impactWood_medium_001", "k/impactWood_medium_002", "k/impactWood_medium_003"], -7.0, 0.15],
	"hit_stone": [["k/impactPlate_medium_000", "k/impactPlate_medium_001", "k/impactPlate_medium_002"], -6.0, 0.1],
	"death_bone": [["k/impactWood_heavy_001", "k/impactWood_heavy_002", "k/impactWood_heavy_003"], -3.0, 0.12],
	"death_player": [["k/impactPunch_heavy_000", "k/impactPunch_heavy_001"], 0.0, 0.05],
	"frozen": [["k/impactGlass_medium_000", "k/impactGlass_medium_001", "k/impactGlass_medium_002"], -5.0, 0.1],
	"footstep": [["k/footstep_grass_000", "k/footstep_grass_001", "k/footstep_grass_002", "k/footstep_grass_003", "k/footstep_grass_004"], -16.0, 0.1],
	# MOBA
	"tower_shot": [["k/laserLarge_000", "k/laserLarge_001", "k/laserLarge_002"], -9.0, 0.06],
	"minion_shot": [["k/laserSmall_000", "k/laserSmall_001", "k/laserSmall_002"], -16.0, 0.12],
	"coins": [["k/handleCoins", "k/handleCoins2"], -2.0, 0.05],
	"level_up": [["s/level_up"], -4.0, 0.0],
	"bell": [["k/impactBell_heavy_000", "k/impactBell_heavy_001"], -3.0, 0.0],
	# Interface e eventos
	"click": [["k/click_001", "k/click_002"], -8.0, 0.05],
	"select": [["k/select_001", "k/select_002"], -8.0, 0.05],
	"error": [["k/error_001"], -6.0, 0.0],
	"open": [["k/open_001"], -6.0, 0.0],
	"close": [["k/close_001"], -6.0, 0.0],
	"victory": [["s/victory"], -2.0, 0.0],
	"defeat": [["s/defeat"], -2.0, 0.0],
	"wave_horn": [["s/wave_horn"], -4.0, 0.0],
	"ambience_meadow": [["s/ambience_meadow"], -6.0, 0.0],
}

# Trilhas por contexto: [calma, combate]. Arquivos CC0 (ver CREDITOS.md).
const TRACKS := {
	"menu": ["menu", "menu"],
	"arena": ["explore", "battle"],
	"moba": ["explore", "battle"],
	"boss": ["boss", "boss"],
}
const TRACK_FILES := {
	"menu": "menu.ogg",
	"explore": "explore.ogg",
	"battle": "battle.mp3",
	"boss": "boss.mp3",
}

var volumes := DEFAULT_VOLUMES.duplicate()
var _streams := {}             # caminho -> AudioStream
var _last_play := {}           # id -> tempo do último toque
var _voices := {}              # id -> quantas tocando
var _music_players: Array[AudioStreamPlayer] = []
var _music_current := 0
var _track := ""
var _context := ""
var _combat_timer := 0.0
var _boss := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_settings()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80.0
		add_child(player)
		_music_players.append(player)
	# Clique em todo botão da interface.
	get_tree().node_added.connect(_on_node_added)


func _setup_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")
	# Um pouco de eco nos efeitos dá sensação de espaço.
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.45
		reverb.damping = 0.6
		reverb.wet = 0.12
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx, reverb)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(sfx, limiter)


# --- Volumes -----------------------------------------------------------------

func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volumes[bus], 0.0001)))
	AudioServer.set_bus_mute(index, volumes[bus] <= 0.001)


func save_settings() -> void:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("volume", bus, volumes[bus])
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	for bus in BUSES:
		set_volume(bus, config.get_value("volume", bus, DEFAULT_VOLUMES[bus]) if loaded else DEFAULT_VOLUMES[bus])


# --- Efeitos -----------------------------------------------------------------

func _stream(file: String) -> AudioStream:
	var path := SFX + ("kenney/%s.ogg" % file.substr(2) if file.begins_with("k/") else "synth/%s.wav" % file.substr(2))
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


# Toca um efeito. `at` pode ser uma posição (Vector3), um nó 3D (segue a posição
# dele no momento) ou null (sem posição: interface). `volume` soma em dB.
func play(id: String, at = null, volume := 0.0) -> void:
	if not SOUNDS.has(id) or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_play.get(id, -10.0) < MIN_GAP or _voices.get(id, 0) >= MAX_VOICES:
		return
	var entry: Array = SOUNDS[id]
	var stream := _stream(entry[0].pick_random())
	if stream == null:
		return
	_last_play[id] = now
	var player: Node
	if at == null:
		var flat := AudioStreamPlayer.new()
		flat.bus = "SFX"
		flat.stream = stream
		flat.volume_db = entry[1] + volume
		flat.pitch_scale = 1.0 + randf_range(-entry[2], entry[2])
		player = flat
		add_child(flat)
		flat.play()
	else:
		var spatial := _spatial(stream, entry[1] + volume)
		spatial.pitch_scale = 1.0 + randf_range(-entry[2], entry[2])
		var scene := get_tree().current_scene
		if scene == null:
			return
		scene.add_child(spatial)
		spatial.global_position = at.global_position if at is Node3D else at
		spatial.play()
		player = spatial
	_voices[id] = _voices.get(id, 0) + 1
	player.finished.connect(func():
		_voices[id] = maxi(_voices.get(id, 1) - 1, 0)
		player.queue_free())


func _spatial(stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var spatial := AudioStreamPlayer3D.new()
	spatial.bus = "SFX"
	spatial.stream = stream
	spatial.volume_db = volume_db
	# A câmera fica a ~18 m do personagem: a distância de referência é grande.
	spatial.unit_size = 16.0
	spatial.max_distance = 55.0
	spatial.attenuation_filter_cutoff_hz = 9000.0
	return spatial


# Som contínuo preso a `parent` (começa parado: use .playing). Volume extra em dB.
func make_loop(id: String, parent: Node, volume := 0.0, bus := "SFX") -> Node:
	if not SOUNDS.has(id):
		return null
	var entry: Array = SOUNDS[id]
	var stream := _looped(_stream(entry[0][0]))
	var player: Node
	if parent is Node3D:
		player = _spatial(stream, entry[1] + volume)
	else:
		player = AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = entry[1] + volume
	player.bus = bus
	parent.add_child(player)
	return player


func _looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var key := "loop:" + stream.resource_path
	if _streams.has(key):
		return _streams[key]
	var copy: AudioStream = stream.duplicate()
	if copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
	elif copy is AudioStreamOggVorbis or copy is AudioStreamMP3:
		copy.loop = true
	_streams[key] = copy
	return copy


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind("click"))


# --- Música ------------------------------------------------------------------

# Contexto da partida: "menu", "arena" ou "moba". Vazio para silêncio.
func music(context: String) -> void:
	_context = context
	_combat_timer = 0.0
	_boss = false
	_refresh_track()


# Avisa que houve luta (o personagem local bateu ou apanhou).
func combat_ping() -> void:
	var was_calm := _combat_timer <= 0.0
	_combat_timer = COMBAT_HOLD
	if was_calm:
		_refresh_track()


# Guardião ou chefe por perto: trilha de chefe.
func set_boss(active: bool) -> void:
	if active != _boss:
		_boss = active
		_refresh_track()


# Fim de partida: a trilha some e entra a fanfarra.
func stinger(id: String) -> void:
	_context = ""
	_refresh_track()
	play(id)


func _process(delta: float) -> void:
	if _combat_timer > 0.0:
		_combat_timer -= delta
		if _combat_timer <= 0.0:
			_refresh_track()


func _refresh_track() -> void:
	var track := ""
	if TRACKS.has(_context):
		var pair: Array = TRACKS["boss"] if _boss and _context != "menu" else TRACKS[_context]
		track = pair[1] if _combat_timer > 0.0 else pair[0]
	if track == _track:
		return
	_track = track
	var old := _music_players[_music_current]
	_music_current = 1 - _music_current
	var new := _music_players[_music_current]
	var tween := create_tween().set_parallel(true)
	tween.tween_property(old, "volume_db", -60.0, FADE)
	tween.chain().tween_callback(old.stop)
	if track.is_empty() or DisplayServer.get_name() == "headless":
		return
	var path: String = MUSIC + TRACK_FILES[track]
	if not ResourceLoader.exists(path):
		return
	if not _streams.has(path):
		_streams[path] = _looped(load(path))
	new.stream = _streams[path]
	new.volume_db = -40.0
	new.play()
	create_tween().tween_property(new, "volume_db", 0.0, FADE)
