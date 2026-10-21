# Teste do MOBA pela rede, com dois processos no mesmo PC (sem janela):
#   godot --headless --path . res://tests/moba_net_smoke.tscn -- --role=host
#   godot --headless --path . res://tests/moba_net_smoke.tscn -- --role=client
# O host fica no Azul e o cliente escolhe o Vermelho; bots completam o 3v3.
# Os dois lados imprimem o que viram; o cliente também compra um item.
extends Node

const Combat = preload("res://scripts/core/combat.gd")
const MobaMap = preload("res://scripts/moba/moba_map.gd")


class Driver extends Node:
	var role := ""
	var time := 0.0
	var step := 0

	func _process(delta: float) -> void:
		time += delta
		var main := get_tree().current_scene
		if role == "host":
			if step == 0:
				Network.my_class = "mage"
				Network.my_loadouts = {}   # elementos padrão da classe
				Network.settings = {"mode": "moba", "bots": true}
				Network.host()
				step = 1
			elif step == 1 and Network.players.size() >= 2 and Network.team_of(Network.players[1]) == Combat.RED:
				Network.start_game()
				step = 2
			elif step == 2 and time > 19.0:
				_report(main)
				step = 3
			elif step == 3 and time > 28.0:
				get_tree().quit()
		else:
			if step == 0 and time > 1.0:
				Network.my_class = "assassin"
				Network.my_loadouts = {}   # elementos padrão da classe
				Network.join("127.0.0.1")
				step = 1
			elif step == 1 and Network.players.size() >= 2:
				Network.set_my_team(Combat.RED)
				step = 2
			elif step == 2 and main != null and main.get("local_player") != null:
				main.local_player.camera = null
				step = 3
			elif step == 3 and time > 8.0:
				print("[client] modo=%s time=%s" % [Network.game_mode(), Combat.TEAM_NAMES[main.local_player.team]])
				main.local_player.request_buy.rpc_id(1, "botas")
				step = 4
			elif step == 4 and time > 22.0:
				_report(main)
				get_tree().quit()

	func _report(main: Node) -> void:
		var champions: Array = get_tree().get_nodes_in_group("players")
		var lines := PackedStringArray()
		lines.append("[%s] estruturas=%d tropas=%d monstros=%d campeões=%d bots=%d" % [role,
			get_tree().get_nodes_in_group("structures").size(), get_tree().get_nodes_in_group("minions").size(),
			get_tree().get_nodes_in_group("enemies").size(), champions.size(),
			champions.filter(func(c): return c.is_bot).size()])
		for champion in champions:
			if not champion.is_bot:
				lines.append("[%s] %s %s time=%s pos=%s ouro=%d itens=%s velocidade+=%.1f" % [role, champion.name,
					champion.cls.label, Combat.TEAM_NAMES[champion.team], champion.position.snapped(Vector3.ONE),
					champion.gold, champion.items, champion.speed_bonus])
		print("\n".join(lines))


func _ready() -> void:
	var driver := Driver.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			driver.role = arg.get_slice("=", 1)
	get_tree().root.add_child.call_deferred(driver)
