# Teste do áudio (precisa de janela: no modo headless o Audio fica mudo).
# Uso: godot --path . tests/audio_smoke.tscn
# Confere se todo som e toda música da tabela carregam, se os loops repetem
# e se a trilha troca de calma para combate.
extends Node

var failures := 0


func _ready() -> void:
	for id in Audio.SOUNDS:
		for file in Audio.SOUNDS[id][0]:
			_check(Audio._stream(file) != null, "som %s (%s)" % [id, file])
	for track in Audio.TRACK_FILES:
		_check(ResourceLoader.exists(Audio.MUSIC + Audio.TRACK_FILES[track]), "música " + track)

	var loop: Node = Audio.make_loop("spray_fire", self)
	var stream = loop.stream
	_check(stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop de feitiço repete")

	Audio.play("bolt")
	_check(Audio._voices.get("bolt", 0) == 1, "efeito tocando")

	for track in Audio.TRACK_FILES:
		_check(Audio._music_stream(track, false) != null, "música carrega: " + track)

	Audio.music("arena")
	_check(Audio._track in Audio.POOLS.calm, "arena começa calma (%s)" % Audio._track)
	Audio.combat_ping()
	_check(Audio._track in Audio.POOLS.calm, "um golpe só não troca a trilha")
	Audio.combat_ping()
	Audio.combat_ping()
	_check(Audio._track in Audio.POOLS.combat, "luta de verdade esquenta a trilha (%s)" % Audio._track)
	Audio.set_boss(true)
	_check(Audio._track in Audio.POOLS.boss, "chefe por perto: trilha de chefe")
	Audio.set_boss(false)
	Audio._combat_timer = 0.01
	Audio._process(0.1)
	_check(Audio._track == "" and Audio._gap_timer > 0.0, "depois da luta: pausa só com o ambiente")
	Audio._process(Audio._gap_timer + 0.1)
	_check(Audio._track in Audio.POOLS.calm, "depois da pausa: outra música calma")
	var picks := {}
	for i in 6:
		picks[Audio._pick_file("amb_bird", Audio.SOUNDS.amb_bird[0])] = true
	_check(picks.size() >= 3, "sons variam (%d arquivos diferentes em 6)" % picks.size())
	var last := ""
	var repeated := false
	for i in 20:
		var file := Audio._pick_file("bolt", Audio.SOUNDS.bolt[0])
		repeated = repeated or file == last
		last = file
	_check(not repeated, "não repete o mesmo arquivo duas vezes seguidas")
	Audio.stinger("victory")
	_check(Audio._track == "", "fim de partida: só a fanfarra")

	print("%s: áudio" % ("OK" if failures == 0 else "FALHA (%d)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("falha " + label)
