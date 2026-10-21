# Sons de uma unidade (filho do personagem/inimigo/tropa/estrutura): golpes
# recebidos, queda, congelar, chamas e passos. Lê o nó Health do pai, que já é
# sincronizado: toca igual em todos os PCs.
extends Node3D

const HIT_GAP := 0.3           # segundos mínimos entre dois sons de golpe
const MIN_HIT := 3.0           # dano acumulado para soar um golpe
const STEP_TIME := 0.34

var material := "flesh"        # flesh (magos), bone (esqueletos), stone (estruturas)
var footsteps := false
var is_local := false          # personagem deste PC: a luta esquenta a música
var attack_sound := ""         # tocado a cada ataque (action_count do pai muda)
var attack_volume := 0.0
var health: Node
var _last_hp := -1.0
var _pending := 0.0
var _hit_timer := 0.0
var _was_dead := false
var _was_frozen := false
var _step_timer := 0.0
var _last_position := Vector3.ZERO
var _burning: Node
var _action := -1


func _ready() -> void:
	health = get_parent().get_node_or_null("Health")
	_burning = Audio.make_loop("burning", self)
	_last_position = global_position


func _process(delta: float) -> void:
	if health == null:
		return
	_hit_timer -= delta
	if _last_hp < 0.0:
		_last_hp = health.hp
		_was_dead = health.dead
	var lost: float = _last_hp - health.hp
	_last_hp = health.hp
	if lost > 0.0 and not health.dead:
		_pending += lost
		if _pending >= MIN_HIT and _hit_timer <= 0.0:
			Audio.play("hit_" + material, self, clampf(_pending / 10.0, 0.0, 4.0) - 2.0)
			_pending = 0.0
			_hit_timer = HIT_GAP
			if is_local:
				Audio.combat_ping()
	if health.dead != _was_dead:
		_was_dead = health.dead
		if health.dead:
			_on_death()
		else:
			Audio.play("heal", self)
	var frozen: bool = health.frozen > 0.0
	if frozen and not _was_frozen:
		Audio.play("frozen", self)
	_was_frozen = frozen
	if _burning != null:
		var burning: bool = health.burning > 0.0 and not health.dead
		if _burning.playing != burning:
			_burning.playing = burning
	if footsteps:
		_update_steps(delta)
	if not attack_sound.is_empty():
		var count: int = get_parent().get("action_count")
		if _action != -1 and count != _action:
			Audio.play(attack_sound, self, attack_volume)
		_action = count


func _on_death() -> void:
	match material:
		"stone":
			Audio.play("explosion", self, 2.0)
			Audio.play("crunch", self)
		"bone":
			pass   # esqueletos somem ao morrer: o som sai no _exit_tree deles
		_:
			Audio.play("death_player", self)


func _update_steps(delta: float) -> void:
	var moved := (global_position - _last_position) * Vector3(1, 0, 1)
	_last_position = global_position
	var speed := moved.length() / maxf(delta, 0.001)
	if speed < 1.0 or health.dead:
		_step_timer = 0.0
		return
	_step_timer -= delta * clampf(speed / 5.0, 0.6, 1.6)
	if _step_timer <= 0.0:
		_step_timer = STEP_TIME
		Audio.play("footstep", self)
