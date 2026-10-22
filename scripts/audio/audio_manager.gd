# Som e música (autoload "Audio"). Só toca: nada aqui afeta a lógica do jogo.
# - play(id, posição): efeito curto; sorteia um dos arquivos (sem repetir o último)
#   e varia o tom, para os sons frequentes não soarem sempre iguais;
# - make_loop(id, pai): som contínuo preso a um nó (feitiços, vento);
# - music(contexto): trilha em rodízio. Na calma, uma música por vez, com pausas
#   só com o ambiente entre elas; o combate só entra quando a luta engrena
#   (vários golpes em poucos segundos) e segura um tempo antes de voltar.
# Volumes por canal (Música, Efeitos, Ambiente) ficam salvos em user://audio.cfg.
extends Node

const SFX := "res://assets/audio/sfx/"
const MUSIC := "res://assets/audio/music/"
const SETTINGS_PATH := "user://audio.cfg"
const BUSES := ["Music", "SFX", "Ambience"]
const BUS_LABELS := {"Music": "Música", "SFX": "Efeitos", "Ambience": "Ambiente"}
const DEFAULT_VOLUMES := {"Music": 0.55, "SFX": 0.75, "Ambience": 0.6}

const MAX_VOICES := 3          # cópias simultâneas do mesmo som
const MAX_TOTAL_VOICES := 20   # efeitos ao mesmo tempo (o resto é pulado)
const MIN_GAP := 0.07          # segundos entre duas cópias do mesmo som
const FADE := 2.5
# Música: entra em combate com COMBAT_ENTER sinais de luta em COMBAT_WINDOW s;
# sai depois de COMBAT_HOLD s sem luta.
const COMBAT_ENTER := 3
const COMBAT_WINDOW := 8.0
const COMBAT_HOLD := 18.0
const CALM_GAP := Vector2(25.0, 50.0)       # silêncio entre músicas calmas
const AFTER_COMBAT_GAP := Vector2(8.0, 15.0)

# id -> [arquivos (k/ = Kenney, s/ = sintetizado), volume em dB, variação de tom]
const SOUNDS := {
	# Carga (toque ao apertar D F G): baixo e com variações, porque toca o tempo todo.
	"element_water": [["s/element_water_v1", "s/element_water_v2", "s/element_water_v3"], -14.0, 0.06],
	"element_life": [["s/element_life_v1", "s/element_life_v2", "s/element_life_v3"], -14.0, 0.06],
	"element_shield": [["s/element_shield_v1", "s/element_shield_v2", "s/element_shield_v3"], -14.0, 0.06],
	"element_cold": [["s/element_cold_v1", "s/element_cold_v2", "s/element_cold_v3"], -14.0, 0.06],
	"element_lightning": [["s/element_lightning_v1", "s/element_lightning_v2", "s/element_lightning_v3"], -14.0, 0.06],
	"element_arcane": [["s/element_arcane_v1", "s/element_arcane_v2", "s/element_arcane_v3"], -14.0, 0.06],
	"element_earth": [["s/element_earth_v1", "s/element_earth_v2", "s/element_earth_v3"], -14.0, 0.06],
	"element_fire": [["s/element_fire_v1", "s/element_fire_v2", "s/element_fire_v3"], -14.0, 0.06],
	"element_void": [["s/element_void_v1", "s/element_void_v2", "s/element_void_v3"], -14.0, 0.06],
	"element_gravity": [["s/element_gravity_v1", "s/element_gravity_v2", "s/element_gravity_v3"], -14.0, 0.06],
	"element_smoke": [["s/element_smoke_v1", "s/element_smoke_v2", "s/element_smoke_v3"], -14.0, 0.06],
	"element_blood": [["s/element_blood_v1", "s/element_blood_v2", "s/element_blood_v3"], -14.0, 0.06],
	# Feitiços
	"spray_fire": [["s/spray_fire"], -6.0, 0.0],
	"spray_water": [["s/spray_water"], -6.0, 0.0],
	"spray_cold": [["s/spray_cold"], -8.0, 0.0],
	"spray_steam": [["s/spray_steam"], -9.0, 0.0],
	"beam_arcane": [["s/beam_arcane"], -6.0, 0.0],
	"beam_life": [["s/beam_life"], -10.0, 0.0],
	"arc": [["s/arc_loop"], -7.0, 0.0],
	"charge": [["s/charge_loop"], -10.0, 0.0],
	"burning": [["s/spray_fire"], -20.0, 0.0],
	"launch": [["s/launch_v1", "s/launch_v2", "s/launch_v3", "s/launch_v4"], -6.0, 0.1],
	"bolt": [["s/bolt_v1", "s/bolt_v2", "s/bolt_v3", "s/bolt_v4"], -4.0, 0.1],
	"heal": [["s/heal_v1", "s/heal_v2", "s/heal_v3"], -8.0, 0.06],
	"whoosh": [["s/whoosh_v1", "s/whoosh_v2", "s/whoosh_v3", "s/whoosh_v4"], -7.0, 0.12],
	"shield_up": [["k/forceField_000", "k/forceField_001", "k/forceField_002"], -7.0, 0.08],
	"stone_up": [["k/impactMining_000", "k/impactMining_001", "k/impactMining_002"], -3.0, 0.1],
	"area": [["k/forceField_003", "k/forceField_004"], -6.0, 0.12],
	"slash": [["k/knifeSlice", "k/knifeSlice2", "k/drawKnife1", "k/drawKnife2"], -5.0, 0.12],
	"chop": [["k/chop"], -4.0, 0.12],
	"bubble_up": [["s/bubble_up_v1", "s/bubble_up_v2", "s/bubble_up_v3"], -6.0, 0.05],
	"mini_meteor": [["s/mini_meteor_v1", "s/mini_meteor_v2", "s/mini_meteor_v3"], -6.0, 0.08],
	"zone_pulse": [["s/zone_pulse_v1", "s/zone_pulse_v2", "s/zone_pulse_v3"], -9.0, 0.1],
	"ultimate_cast": [["s/ultimate_cast"], -4.0, 0.04],
	"mega_cast": [["s/mega_cast"], -2.0, 0.03],
	# Explosões por elemento (áreas e ultimates)
	"burst_water": [["s/burst_water_1", "s/burst_water_2", "s/burst_water_3"], -5.0, 0.1],
	"burst_fire": [["s/burst_fire_1", "s/burst_fire_2", "s/burst_fire_3"], -5.0, 0.1],
	"burst_magic": [["s/burst_magic_1", "s/burst_magic_2", "s/burst_magic_3", "s/burst_magic_4"], -6.0, 0.12],
	# Impactos
	"impact_rock": [["k/impactMining_003", "k/impactMining_004", "k/impactWood_heavy_000"], -3.0, 0.1],
	"impact_ice": [["k/impactGlass_heavy_000", "k/impactGlass_heavy_001", "k/impactGlass_heavy_002"], -5.0, 0.1],
	"impact_magic": [["k/impactGeneric_light_000", "k/impactGeneric_light_001", "k/impactGeneric_light_002"], -4.0, 0.15],
	"explosion": [["k/lowFrequency_explosion_000", "k/lowFrequency_explosion_001"], -1.0, 0.1],
	"crunch": [["k/explosionCrunch_000", "k/explosionCrunch_001", "k/explosionCrunch_002"], -5.0, 0.12],
	"hit_flesh": [["k/impactPunch_medium_000", "k/impactPunch_medium_001", "k/impactPunch_medium_002", "k/impactPunch_medium_003"], -8.0, 0.15],
	"hit_bone": [["k/impactWood_medium_000", "k/impactWood_medium_001", "k/impactWood_medium_002", "k/impactWood_medium_003"], -9.0, 0.18],
	"hit_stone": [["k/impactPlate_medium_000", "k/impactPlate_medium_001", "k/impactPlate_medium_002"], -7.0, 0.12],
	"death_bone": [["k/impactWood_heavy_001", "k/impactWood_heavy_002", "k/impactWood_heavy_003"], -4.0, 0.12],
	"death_player": [["k/impactPunch_heavy_000", "k/impactPunch_heavy_001"], -1.0, 0.05],
	"frozen": [["k/impactGlass_medium_000", "k/impactGlass_medium_001", "k/impactGlass_medium_002"], -6.0, 0.1],
	"footstep": [["k/footstep_grass_000", "k/footstep_grass_001", "k/footstep_grass_002", "k/footstep_grass_003", "k/footstep_grass_004"], -22.0, 0.15],
	# MOBA
	"tower_shot": [["k/laserLarge_000", "k/laserLarge_001", "k/laserLarge_002"], -10.0, 0.08],
	"minion_shot": [["k/laserSmall_000", "k/laserSmall_001", "k/laserSmall_002"], -18.0, 0.15],
	"coins": [["k/handleCoins", "k/handleCoins2"], -4.0, 0.08],
	"level_up": [["s/level_up"], -4.0, 0.0],
	"bell": [["k/impactBell_heavy_000", "k/impactBell_heavy_001"], -3.0, 0.0],
	# Interface e eventos
	"click": [["k/click_001", "k/click_002"], -10.0, 0.08],
	"select": [["k/select_001", "k/select_002"], -8.0, 0.05],
	"error": [["k/error_001"], -8.0, 0.05],
	"open": [["k/open_001"], -6.0, 0.0],
	"close": [["k/close_001"], -6.0, 0.0],
	"victory": [["s/victory"], -2.0, 0.0],
	"defeat": [["s/defeat"], -2.0, 0.0],
	"wave_horn": [["s/wave_horn"], -4.0, 0.0],
	# Ambiente (ambience.gd): vento de fundo e sons soltos espalhados em volta.
	"amb_wind_bed": [["s/amb_wind_bed"], -10.0, 0.0],
	"amb_bird": [["s/amb_bird_1", "s/amb_bird_2", "s/amb_bird_3", "s/amb_bird_4", "s/amb_bird_5", "s/amb_bird_6", "s/amb_bird_7", "s/amb_bird_8"], -14.0, 0.12],
	"amb_insect": [["s/amb_insect_1", "s/amb_insect_2", "s/amb_insect_3"], -20.0, 0.08],
	"amb_rustle": [["s/amb_rustle_1", "s/amb_rustle_2", "s/amb_rustle_3", "s/amb_rustle_4"], -16.0, 0.1],
	"amb_distant": [["s/amb_distant_1", "s/amb_distant_2"], -16.0, 0.06],
}

# Trilhas (arquivos CC0, ver CREDITOS.md) e o volume de cada uma em dB.
const TRACK_FILES := {
	"menu": "menu.ogg",
	"explore": "explore.ogg",
	"field_of_dreams": "field_of_dreams.mp3",
	"bards_tale": "bards_tale.mp3",
	"town_theme": "town_theme.mp3",
	"battle": "battle.mp3",
	"night_prowler": "night_prowler.ogg",
	"unrest": "unrest.ogg",
	"boss": "boss.mp3",
	"fantasy_choir": "fantasy_choir.mp3",
}
const TRACK_VOLUME := {"explore": -3.0, "field_of_dreams": -5.0, "bards_tale": -5.0, "town_theme": -4.0}
# Clima -> músicas possíveis (sorteadas sem repetir a anterior).
const POOLS := {
	"menu": ["menu"],
	"calm": ["explore", "field_of_dreams", "bards_tale", "town_theme"],
	"combat": ["battle", "night_prowler", "unrest"],
	"boss": ["boss", "fantasy_choir"],
}

var volumes := DEFAULT_VOLUMES.duplicate()
var _streams := {}             # caminho -> AudioStream
var _last_play := {}           # id -> tempo do último toque
var _voices := {}              # id -> quantas tocando
var _last_file := {}           # id -> último arquivo tocado (para não repetir)
var _active := 0               # efeitos tocando agora
var _music_players: Array[AudioStreamPlayer] = []
var _music_current := 0
var _track := ""               # música tocando ("" = pausa ou silêncio)
var _mood := ""                # "", "menu", "calm", "combat" ou "boss"
var _context := ""
var _combat_timer := 0.0
var _pings: Array = []         # momentos dos últimos sinais de luta
var _gap_timer := 0.0          # pausa sem música (só o ambiente)
var _last_track := {}          # clima -> última música tocada
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
		player.finished.connect(_on_music_finished.bind(player))
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
# dele no momento) ou null (sem posição: interface). `volume` soma em dB;
# `pitch` multiplica o tom (além da variação sorteada); `bus`: canal de volume.
func play(id: String, at = null, volume := 0.0, pitch := 1.0, bus := "SFX") -> void:
	if not SOUNDS.has(id) or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_play.get(id, -10.0) < MIN_GAP or _voices.get(id, 0) >= MAX_VOICES:
		return
	if _active >= MAX_TOTAL_VOICES:
		return
	var entry: Array = SOUNDS[id]
	var stream := _stream(_pick_file(id, entry[0]))
	if stream == null:
		return
	_last_play[id] = now
	var player: Node
	if at == null:
		var flat := AudioStreamPlayer.new()
		flat.bus = bus
		flat.stream = stream
		flat.volume_db = entry[1] + volume
		flat.pitch_scale = pitch * (1.0 + randf_range(-entry[2], entry[2]))
		player = flat
		add_child(flat)
		flat.play()
	else:
		var spatial := _spatial(stream, entry[1] + volume)
		spatial.bus = bus
		spatial.pitch_scale = pitch * (1.0 + randf_range(-entry[2], entry[2]))
		var scene := get_tree().current_scene
		if scene == null:
			return
		scene.add_child(spatial)
		spatial.global_position = at.global_position if at is Node3D else at
		spatial.play()
		player = spatial
	_voices[id] = _voices.get(id, 0) + 1
	_active += 1
	player.finished.connect(func():
		_voices[id] = maxi(_voices.get(id, 1) - 1, 0)
		_active = maxi(_active - 1, 0)
		player.queue_free())


# Um dos arquivos do som, sem repetir o da última vez (quando há mais de um).
func _pick_file(id: String, files: Array) -> String:
	if files.size() == 1:
		return files[0]
	var choices := files.filter(func(file): return file != _last_file.get(id, ""))
	var file: String = choices.pick_random()
	_last_file[id] = file
	return file


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

# Contexto da partida: "menu", "arena", "moba" ou "practice". Vazio para silêncio.
func music(context: String) -> void:
	_context = context
	_combat_timer = 0.0
	_pings = []
	_boss = false
	_mood = ""
	_refresh_track()


# Sinal de luta (o personagem local bateu ou apanhou perto de inimigos). A trilha
# de combate só entra com vários sinais seguidos; depois, cada sinal a segura.
func combat_ping() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_pings.append(now)
	while not _pings.is_empty() and now - _pings[0] > COMBAT_WINDOW:
		_pings.pop_front()
	if _mood == "combat" or _pings.size() >= COMBAT_ENTER:
		_combat_timer = COMBAT_HOLD
		if _mood != "combat":
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
			_pings = []
			_refresh_track()
	if _gap_timer > 0.0:
		_gap_timer -= delta
		if _gap_timer <= 0.0 and _mood == "calm":
			_start_track(_pick_track("calm"), false)


func _wanted_mood() -> String:
	if _context.is_empty():
		return ""
	if _context == "menu":
		return "menu"
	if _boss:
		return "boss"
	return "combat" if _combat_timer > 0.0 else "calm"


func _refresh_track() -> void:
	var mood := _wanted_mood()
	if mood == _mood:
		return
	var from_combat := _mood == "combat" or _mood == "boss"
	_mood = mood
	_gap_timer = 0.0
	match mood:
		"":
			_start_track("", false)
		"calm":
			if from_combat:
				# Depois da luta, um respiro só com o ambiente antes da próxima música.
				_start_track("", false)
				_gap_timer = randf_range(AFTER_COMBAT_GAP.x, AFTER_COMBAT_GAP.y)
			else:
				_start_track(_pick_track("calm"), false)
		_:
			_start_track(_pick_track(mood), true)


# Música do clima, sorteada sem repetir a última dele.
func _pick_track(mood: String) -> String:
	var pool: Array = POOLS[mood]
	var choices := pool.filter(func(track): return track != _last_track.get(mood, "")) if pool.size() > 1 else pool
	var track: String = choices.pick_random()
	_last_track[mood] = track
	return track


# Troca para `track` com fade ("" = silêncio). `loop`: repete (combate, chefe, menu).
func _start_track(track: String, loop: bool) -> void:
	if track == _track and not track.is_empty():
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
	var stream := _music_stream(track, loop or _mood == "menu")
	if stream == null:
		return
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	create_tween().tween_property(new, "volume_db", TRACK_VOLUME.get(track, 0.0), FADE)


func _music_stream(track: String, loop: bool) -> AudioStream:
	var path: String = MUSIC + TRACK_FILES[track]
	var key := "%s|%s" % [path, loop]
	if _streams.has(key):
		return _streams[key]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path).duplicate()
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = loop
	_streams[key] = stream
	return stream


# Música calma acabou: pausa só com o ambiente e depois outra música.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _music_players[_music_current] or _mood != "calm":
		return
	_track = ""
	_gap_timer = randf_range(CALM_GAP.x, CALM_GAP.y)
