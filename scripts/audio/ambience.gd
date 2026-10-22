# Ambiente da partida (filho do game_audio, só neste PC): em vez de um loop curto
# que repete, um vento de fundo longo e sons soltos (pássaros, grilos, folhas,
# um pio distante) que aparecem em tempos aleatórios, de lugares aleatórios em
# volta do jogador, com tom e volume variando. Durante a luta, a natureza se cala
# um pouco (menos pássaros).
extends Node3D

# id do som -> [intervalo mínimo, máximo em s, distância mínima, máxima em m]
const LAYERS := {
	"amb_bird": [6.0, 16.0, 10.0, 26.0],
	"amb_rustle": [9.0, 22.0, 6.0, 18.0],
	"amb_insect": [14.0, 30.0, 8.0, 20.0],
	"amb_distant": [35.0, 80.0, 28.0, 40.0],
}
const COMBAT_SLOWDOWN := 2.5     # em luta, os sons soltos ficam mais raros

var main: Node
var _bed: Node
var _timers := {}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_bed = Audio.make_loop("amb_wind_bed", self, 0.0, "Ambience")
	if _bed != null:
		_bed.play(randf() * 50.0)
	for id in LAYERS:
		# Cada camada começa em um momento diferente.
		_timers[id] = randf_range(2.0, LAYERS[id][1])


func _process(delta: float) -> void:
	if _bed == null:
		return
	var listener := _listener()
	if listener == null:
		return
	global_position = listener.global_position
	var calm_rate := 1.0 / COMBAT_SLOWDOWN if Audio._mood == "combat" or Audio._mood == "boss" else 1.0
	for id in LAYERS:
		_timers[id] -= delta * calm_rate
		if _timers[id] > 0.0:
			continue
		var layer: Array = LAYERS[id]
		_timers[id] = randf_range(layer[0], layer[1])
		var angle := randf() * TAU
		var distance := randf_range(layer[2], layer[3])
		var at: Vector3 = listener.global_position + Vector3(cos(angle), randf_range(1.0, 4.0), sin(angle)) * distance
		Audio.play(id, at, randf_range(-4.0, 0.0), randf_range(0.92, 1.08), "Ambience")


func _listener() -> Node3D:
	var player = main.get("local_player") if main != null else null
	return player if is_instance_valid(player) else null
