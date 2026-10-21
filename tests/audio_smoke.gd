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

	Audio.music("arena")
	_check(Audio._track == "explore", "arena começa calma")
	Audio.combat_ping()
	_check(Audio._track == "battle", "luta esquenta a trilha")
	Audio.set_boss(true)
	_check(Audio._track == "boss", "chefe por perto: trilha de chefe")
	Audio.stinger("victory")
	_check(Audio._track == "", "fim de partida: só a fanfarra")

	print("%s: áudio" % ("OK" if failures == 0 else "FALHA (%d)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("falha " + label)
