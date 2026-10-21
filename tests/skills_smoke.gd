# Teste das skills (Q W E R) das 3 classes e dos ultimates (com os MEGA) em partida solo (sem janela):
#   godot --headless --path . res://tests/skills_smoke.tscn
# Usa os mesmos pedidos que o jogador faz (request_charge, request_skill...),
# reiniciando a partida para trocar de classe. Termina com código 0 se tudo passar.
extends Node

const E = preload("res://scripts/core/elements.gd")


class Driver extends Node:
	var main: Node
	var player: Node
	var dummy: Node
	var dummy2: Node
	var failures := 0

	func _ready() -> void:
		await _start("mage")
		await _test_mage()
		await _test_ultimates()
		await _start("assassin")
		await _test_assassin()
		await _start("fighter")
		await _test_fighter()
		print("skills: %s" % ("OK" if failures == 0 else "%d falha(s)" % failures))
		get_tree().quit(1 if failures > 0 else 0)

	# Escolhe a classe (elementos padrão, sem salvar no PC) e (re)inicia a partida.
	func _start(class_id: String) -> void:
		Network.my_class = class_id
		Network.my_loadouts = {}
		if not Network.is_online():
			Network.host()
			Network.start_game()
		else:
			Network.classes[1] = class_id
			Network.loadouts[1] = Network.my_elements()
			Network.restart_game()
		var old_id := main.get_instance_id() if main != null else 0
		await _wait_until(func(): return _scene_ready(old_id))
		main.game_state.timer = 9999.0   # sem ondas durante o teste
		player.global_position = Vector3.ZERO
		await _seconds(0.2)
		dummy = await _spawn_dummy()

	func _scene_ready(old_id: int) -> bool:
		var scene := get_tree().current_scene
		if scene == null or scene.get_instance_id() == old_id or scene.get("local_player") == null or scene.get("game_state") == null:
			return false
		main = scene
		player = main.local_player
		player.camera = null
		return true

	# --- Mago ---

	func _test_mage() -> void:
		_check(is_equal_approx(player.max_mana, 160.0), "Mago: 160 de mana")
		_place(Vector3(0, 0, -5))
		await _skill("q")
		await _seconds(0.5)
		_check(is_equal_approx(500.0 - dummy.health.hp, 30.0), "Orbe sem carga: 30 de dano (%d)" % (500 - dummy.health.hp))

		_place(Vector3(0, 0, -5))
		player.health.blinded = 5.0
		await _skill("q")
		await _seconds(0.5)
		_check(is_equal_approx(500.0 - dummy.health.hp, 15.0), "cego (Fumaça): metade do dano (%d)" % (500 - dummy.health.hp))

		var T = E.Type
		# Orbe volátil: com Fogo fica maior e explode em área (pega o 2º alvo).
		dummy2 = await _spawn_dummy()
		_place(Vector3(0, 0, -5))
		_reset(dummy2, Vector3(1.6, 0, -5.6))
		player.request_charge(0)   # Fogo (Fogo, Raio, Arcano)
		await _skill("q")
		await _seconds(0.5)
		_check(dummy.health.hp < 500.0 - 30.0 and dummy2.health.hp < 500.0,
			"Orbe com Fogo explode em área (alvo %d, vizinho %d)" % [dummy.health.hp, dummy2.health.hp])
		_reset(dummy2, Vector3(30, 0, 30))

		# W segurado: bolha de escudo (Terra: absorve mais); Fogo queima quem está dentro.
		_place(Vector3(0, 0, -2))
		player.queue.add(T.EARTH)
		player.queue.add(T.FIRE)
		player.request_skill_held("w", dummy.global_position, "")
		_check(player.bubble_time > 0.0 and is_equal_approx(player.health.barrier_hp, 100.0),
			"W segurado: bolha com barreira de 100 (Terra)")
		var hp: float = player.health.hp
		player.health.damage(40.0)
		_check(is_equal_approx(player.health.hp, hp) and is_equal_approx(player.health.barrier_hp, 60.0), "a barreira absorve o dano")
		await _seconds(0.4)
		_check(dummy.health.burning > 0.0, "bolha com Fogo queima o inimigo dentro")
		player.bubble_time = 0.0
		player.request_skill_held("q", dummy.global_position, "")
		_check(player.skill_cooldowns.get("q", 0.0) == 0.0, "só o W tem versão segurada")

		# E: Mini meteoro com Fogo: impacto + chão em brasa (dano por segundo).
		_place(Vector3(0, 0, -6))
		player.request_charge(0)
		await _skill("e")
		await _seconds(0.75)
		var impact: float = 500.0 - dummy.health.hp
		_check(impact >= 40.0, "Mini meteoro: dano do impacto (%d)" % impact)
		await _seconds(1.5)
		_check(500.0 - dummy.health.hp > impact + 10.0 and dummy.health.burning > 0.0,
			"Mini meteoro com Fogo: queima por 3 s (%d -> %d)" % [impact, 500 - dummy.health.hp])
		await _seconds(2.0)

		# Mini meteoro com Gravidade: magnetismo puxa para o centro.
		_place(Vector3(2.5, 0, -6))
		player.queue.add(T.GRAVITY)
		player.request_skill("e", Vector3(0, 0, -6), "")
		await _seconds(1.2)
		_check(dummy.push_velocity.x < -3.0, "Mini meteoro com Gravidade puxa para o centro (%.1f)" % dummy.push_velocity.x)
		await _seconds(2.5)

		_fresh()
		player.mana = 10.0
		await _skill("q")
		_check(player.skill_cooldowns.get("q", 0.0) == 0.0 and player.mana < 11.0, "sem mana a skill não sai")
		player.mana = player.max_mana

	# --- Ultimates (com o Mago; a carga é montada direto com os elementos) ---

	func _test_ultimates() -> void:
		var T = E.Type
		# Terremoto (Terra dominante) com Fogo de reforço: dano, atordoa e queima.
		_place(Vector3(0, 0, -4))
		await _ultimate([T.EARTH, T.EARTH, T.FIRE], dummy.global_position)
		_check(dummy.health.stunned > 0.0 and dummy.health.burning > 0.0 and dummy.health.hp < 450.0,
			"Terremoto + Fogo: dano, atordoa e queima (hp=%d)" % dummy.health.hp)

		_place(Vector3(0, 0, -8))
		await _ultimate([T.ARCANE], dummy.global_position)
		_check(is_equal_approx(dummy.health.hp, 500.0), "Cataclismo espera antes de explodir")
		await _seconds(1.2)
		_check(dummy.health.hp < 400.0, "Cataclismo explode no cursor (hp=%d)" % dummy.health.hp)

		_place(Vector3(0, 0, -4))
		await _ultimate([T.WATER], dummy.global_position)
		_check(dummy.health.wet > 0.0 and dummy.push_velocity.z < -5.0, "Maremoto molha e empurra (%.1f)" % dummy.push_velocity.z)

		_place(Vector3(0, 0, -5))
		await _ultimate([T.COLD], dummy.global_position)
		_check(dummy.health.frozen > 3.0, "Inverno congela")

		_place(Vector3(0, 0, -5))
		await _ultimate([T.LIGHTNING], dummy.global_position)
		await _seconds(1.2)
		_check(dummy.health.hp < 500.0, "Tempestade (hp=%d)" % dummy.health.hp)

		player.health.damage(120.0)
		await _ultimate([T.LIFE], player.global_position)
		_check(player.health.hp >= 200.0 - 120.0 + 59.0, "Bênção cura (hp=%d)" % player.health.hp)

		# Novos elementos.
		_place(Vector3(0, 0, -6))
		dummy.health.shielded = 10.0
		await _ultimate([T.VOID], dummy.global_position)
		_check(dummy.health.shielded == 0.0 and dummy.health.hp < 500.0, "Eclipse desfaz o escudo (hp=%d)" % dummy.health.hp)

		_place(Vector3(4, 0, -6))
		await _ultimate([T.GRAVITY], Vector3(0, 0, -6))
		_check(dummy.health.stunned > 0.0 and dummy.push_velocity.x < -5.0, "Singularidade suga para o cursor e atordoa (%.1f)" % dummy.push_velocity.x)

		_place(Vector3(0, 0, -5))
		await _ultimate([T.SMOKE], dummy.global_position)
		_check(dummy.health.blinded > 0.0 and player.invisible > 0.0, "Cortina de fumaça: inimigo cego e você invisível")
		player.invisible = 0.0

		_place(Vector3(0, 0, -6))
		player.queue.add(T.GRAVITY)
		player.skill_cooldowns = {}
		await _skill("q")
		await _seconds(0.5)
		_check(dummy.push_velocity.z > 3.0, "Orbe com Gravidade puxa o alvo (%.1f)" % dummy.push_velocity.z)

		await _ultimate([T.SHIELD], player.global_position)
		await _seconds(0.2)
		var barriers := get_tree().current_scene.get_children().filter(func(node): return node is StaticBody3D and node.get("elements") != null)
		_check(player.health.shielded > 0.0 and barriers.size() == 8, "Fortaleza: 8 barreiras e escudo (%d)" % barriers.size())

		# Sangue.
		_place(Vector3(0, 0, -4))
		player.health.damage(100.0)
		var before: float = player.health.hp
		await _ultimate([T.BLOOD], player.global_position)
		_check(dummy.health.bleeding > 0.0 and player.health.hp > before, "Lua de sangue: sangra e cura (%d -> %d)" % [before, player.health.hp])

		# Voláteis: secundário deixa zona; 3 iguais = MEGA.
		_place(Vector3(0, 0, -8))
		await _ultimate([T.ARCANE, T.ARCANE, T.GRAVITY], dummy.global_position)
		await _seconds(0.1)
		_check(_zones().any(func(zone): return zone.elements == [T.GRAVITY]), "Cataclismo + Gravidade deixa zona de Gravidade")
		await _seconds(3.2)

		_place(Vector3(0, 0, -5))
		await _ultimate([T.SMOKE, T.SMOKE, T.SMOKE], player.global_position)
		await _seconds(0.3)
		_check(dummy.health.blackout > 0.0 and dummy.health.blinded > 0.0 and player.invisible > 0.0,
			"Mega fumaça: inimigo cego e sem visão, você invisível")
		await _seconds(3.0)

		_place(Vector3(0, 0, -6))
		await _ultimate([T.VOID, T.VOID, T.VOID], player.global_position)
		_check(dummy.health.silenced > 0.0, "Apagão silencia")

		_place(Vector3(0, 0, -7))
		await _ultimate([T.FIRE, T.FIRE, T.FIRE], dummy.global_position)
		await _seconds(1.2)
		var meteors := get_tree().current_scene.get_children().filter(func(node): return node.get("zone_elements") != null)
		_check(meteors.size() >= 2 and dummy.health.hp < 500.0, "Chuva de meteoros (%d meteoros, hp=%d)" % [meteors.size(), dummy.health.hp])
		await _seconds(1.5)

		_place(Vector3(0, 0, -4))
		player.health.damage(60.0)
		await _ultimate([T.SHIELD, T.SHIELD, T.SHIELD], player.global_position)
		var hp: float = player.health.hp
		player.health.damage(500.0)
		_check(is_equal_approx(player.health.hp, hp) and not player.health.dead, "Bastião: invulnerável")
		player.health.reset()

		_place(Vector3(0, 0, -8))
		await _ultimate([T.GRAVITY, T.GRAVITY, T.GRAVITY], dummy.global_position + Vector3(3, 0, 0))
		await _seconds(0.6)
		_check(dummy.push_velocity.x > 2.0 and dummy.health.hp < 500.0, "Buraco negro suga e fere (%.1f)" % dummy.push_velocity.x)
		await _seconds(4.0)

	# --- Assassino ---

	func _test_assassin() -> void:
		var T = E.Type
		_check(player.cls.label == "Assassino" and is_equal_approx(player.max_mana, 110.0), "Assassino: 110 de mana")
		# Adaga de frente e pelas costas (o alvo virado para o mesmo lado da adaga).
		_place(Vector3(0, 0, -5), PI)    # virado para o jogador (inimigos olham para -Z)
		await _skill("q")
		await _seconds(0.4)
		var front: float = 500.0 - dummy.health.hp
		_place(Vector3(0, 0, -5), 0.0)   # de costas
		await _seconds(2.1)
		await _skill("q")
		await _seconds(0.4)
		var back: float = 500.0 - dummy.health.hp
		_check(front > 15.0 and is_equal_approx(back, front * 2.0), "Adaga pelas costas: 2x (%d -> %d)" % [front, back])

		_place(Vector3(0, 0, -4))
		await _skill("w", dummy)
		_check(dummy.health.vulnerable > 0.0, "W no inimigo: Marca")
		await _seconds(10.1)
		await _skill("w")
		_check(player.invisible > 0.0, "W em si mesmo: Véu (invisível)")

		# Passo sombrio com Frio: salta e solta a carga onde cai.
		_place(Vector3(0, 0, -7))
		player.request_charge(1)   # Frio (Arcano, Frio, Terra)
		await _skill("e")
		await _seconds(0.2)
		_check(player.global_position.z < -4.0, "Passo sombrio salta 6 m (%s)" % player.global_position.snapped(Vector3.ONE * 0.1))
		_check(dummy.health.chilled > 0.0 and dummy.health.hp < 500.0, "Passo sombrio solta a carga onde cai (hp=%d)" % dummy.health.hp)
		_check(player.invisible == 0.0, "agir revela o Assassino")

		# W com Vida/Escudo: sempre para ele mesmo, mesmo mirando no inimigo.
		_place(Vector3(0, 0, -4))
		player.health.damage(60.0)
		var hp: float = player.health.hp
		dummy.health.damage(100.0)
		player.queue.add(T.LIFE)
		await _skill("w", dummy)
		_check(player.health.hp > hp + 20.0 and is_equal_approx(dummy.health.hp, 400.0),
			"Assassino: Vida no W cura ele mesmo (%d -> %d), não o inimigo" % [hp, player.health.hp])
		_fresh()
		player.queue.add(T.SHIELD)
		await _skill("w", dummy)
		_check(player.health.barrier_hp > 0.0, "Assassino: Escudo no W dá escudo para ele mesmo")

		# Sangue: em si mesmo dá roubo de vida; nas skills de dano, rouba vida.
		_fresh()
		player.queue.add(T.BLOOD)
		await _skill("w")
		_check(player.health.lifesteal > 0.0, "Sangue no W em si mesmo: roubo de vida")
		_place(Vector3(0, 0, -5), PI)
		player.health.damage(80.0)
		hp = player.health.hp
		player.queue.add(T.BLOOD)
		await _skill("q")
		await _seconds(0.4)
		_check(dummy.health.bleeding > 0.0 and player.health.hp > hp, "Adaga com Sangue: sangramento e roubo de vida (%d -> %d)" % [hp, player.health.hp])

	# --- Lutador ---

	func _test_fighter() -> void:
		var T = E.Type
		_check(player.cls.label == "Lutador" and is_equal_approx(player.health.max_hp, 320.0), "Lutador: 320 de vida")
		_place(Vector3(0, 0, -1.8))
		player.request_charge(0)   # Fogo
		await _skill("q")
		await _seconds(0.2)
		_check(dummy.health.burning > 0.0 and dummy.health.hp < 500.0 - 28.0 and dummy.push_velocity.z < -3.0,
			"Golpe giratório: dano, carga e empurrão (hp=%d)" % dummy.health.hp)

		await _skill("w")
		_check(player.health.hasted > 0.0 and player.health.fortified > 0.0, "W em si mesmo: Grito (acelera e fortifica)")
		var hp: float = player.health.hp
		player.health.damage(100.0)
		_check(is_equal_approx(hp - player.health.hp, 100.0 * 0.75 * 0.7), "armadura 25% + fortificado 30%")

		_place(Vector3(0, 0, -4))
		await _skill("e")
		await _seconds(0.6)
		_check(dummy.health.hp < 500.0 - 20.0, "Investida atropela (hp=%d)" % dummy.health.hp)

	# --- Ajudantes ---

	# Alvo: um lacaio que não anda nem ataca (sem física: empurrões ficam em push_velocity).
	func _spawn_dummy() -> Node:
		main.spawn_entity({"type": "enemy", "kind": "grunt", "pos": Vector3(0, 0, -5)})
		await _seconds(0.2)
		var spawned: Node = get_tree().get_nodes_in_group("enemies").filter(func(node): return node != dummy)[0]
		spawned.set_physics_process(false)
		spawned.health.max_hp = 500.0
		spawned.health.reset()
		return spawned

	# Põe o alvo (vida cheia) em `at`, virado para `yaw`, e o personagem na origem pronto.
	func _place(at: Vector3, yaw := 0.0) -> void:
		dummy.health.reset()
		dummy.push_velocity = Vector3.ZERO
		dummy.global_position = at
		dummy.rotation.y = yaw
		player.global_position = Vector3.ZERO
		_fresh()

	func _reset(target: Node, at: Vector3) -> void:
		target.health.reset()
		target.push_velocity = Vector3.ZERO
		target.global_position = at

	func _zones() -> Array:
		return get_tree().current_scene.get_children().filter(func(node): return node.get("dps") != null and node.get("elements") != null)

	# Sem recargas, mana cheia e carga vazia.
	func _fresh() -> void:
		player.skill_cooldowns = {}
		player.mana = player.max_mana
		player._clear_queue()
		player.health.reset()

	# Usa a skill mirando no alvo de teste (ou em `target`, para o W).
	func _skill(slot: String, target: Node = null) -> void:
		player.aim_point = dummy.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		var target_name := String(target.name) if target != null else ""
		player.request_skill(slot, dummy.global_position, target_name)

	func _ultimate(charge: Array, point: Vector3) -> void:
		player.skill_cooldowns = {}
		player.mana = player.max_mana
		player._clear_queue()
		for element in charge:
			player.queue.add(element)
		player.request_skill("r", point, "")
		await _seconds(0.05)

	func _check(condition: bool, message: String) -> void:
		print(("ok    " if condition else "FALHOU ") + message)
		if not condition:
			failures += 1

	func _seconds(time: float) -> void:
		await get_tree().create_timer(time).timeout

	func _wait_until(condition: Callable) -> void:
		while not condition.call():
			await get_tree().process_frame


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())
