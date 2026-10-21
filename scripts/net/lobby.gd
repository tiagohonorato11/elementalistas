# Tela inicial: hospedar, jogar sozinho, entrar em partida encontrada ou por IP.
# Linha de comando (útil para testes): -- --host | --solo | --join=IP | --autostart=N | --class=ID | --mode=arena|moba
extends Control

const Classes = preload("res://scripts/core/classes.gd")
const Combat = preload("res://scripts/core/combat.gd")

enum State { MENU, HOSTING, CONNECTING, CONNECTED }

var state := State.MENU
var menu_box: VBoxContainer
var games_box: VBoxContainer
var ip_edit: LineEdit
var wait_box: VBoxContainer
var wait_label: Label
var start_button: Button
var status_label: Label
var class_buttons := {}   # id da classe -> Button
var class_description: Label
var mode_buttons := {}    # id do modo -> Button
var team_row: HBoxContainer
var team_buttons := {}    # time -> Button
var bots_check: CheckBox

var _games_signature := "?"
var _games_timer := 0.0
var _autostart := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	Audio.music("menu")
	Network.players_changed.connect(_refresh)
	Network.connected.connect(func(): _set_state(State.CONNECTED))
	Network.connection_failed.connect(_on_connection_failed)
	Network.start_listening()
	status_label.text = Network.last_message
	Network.last_message = ""
	_set_state(State.MENU)
	_parse_command_line.call_deferred()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(480, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	var title := _label(column, "Elementistas", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Escolha de classe: vale em qualquer estado do lobby.
	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 8)
	column.add_child(class_row)
	_label(class_row, "Classe:", 18)
	for id in Classes.ORDER:
		var button := _button(class_row, Classes.info(id).label, _on_class_pressed.bind(id))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		class_buttons[id] = button
	class_description = _label(column, "", 15)
	class_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	class_description.custom_minimum_size.x = 480
	_refresh_class()

	# Modo de jogo (o host escolhe) e, no MOBA, time e bots.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	column.add_child(mode_row)
	_label(mode_row, "Modo:", 18)
	for id in Network.MODES:
		var button := _button(mode_row, Network.MODES[id], _on_mode_pressed.bind(id))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_buttons[id] = button
	team_row = HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	column.add_child(team_row)
	_label(team_row, "Time:", 18)
	for team in [Combat.BLUE, Combat.RED]:
		var button := _button(team_row, Combat.TEAM_NAMES[team], _on_team_pressed.bind(team))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		team_buttons[team] = button
	bots_check = CheckBox.new()
	bots_check.text = "Completar os times com bots (3v3)"
	bots_check.toggled.connect(func(on): Network.set_setting("bots", on))
	column.add_child(bots_check)

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	column.add_child(menu_box)
	_button(menu_box, "Hospedar partida", _on_host_pressed)
	_button(menu_box, "Jogar sozinho", _on_solo_pressed)
	_button(menu_box, "Configurações", func(): get_tree().change_scene_to_file("res://scenes/settings.tscn"))
	_label(menu_box, "Partidas encontradas no Wi-Fi:", 18)
	games_box = VBoxContainer.new()
	menu_box.add_child(games_box)
	_label(menu_box, "Ou digite o IP do host:", 18)
	var row := HBoxContainer.new()
	menu_box.add_child(row)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "ex.: 192.168.0.10"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(_join)
	row.add_child(ip_edit)
	_button(row, "Entrar", func(): _join(ip_edit.text))

	wait_box = VBoxContainer.new()
	wait_box.add_theme_constant_override("separation", 8)
	column.add_child(wait_box)
	wait_label = _label(wait_box, "", 20)
	start_button = _button(wait_box, "Começar partida", _on_start_pressed)
	_button(wait_box, "Cancelar", _on_cancel_pressed)

	status_label = _label(column, "", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


func _process(delta: float) -> void:
	if state != State.MENU:
		return
	_games_timer -= delta
	if _games_timer > 0.0:
		return
	_games_timer = 0.5
	# Só recria os botões quando a lista muda, para não perder cliques.
	var signature := str(Network.found_games.keys()) + str(Network.found_games.values().map(func(g): return g.players))
	if signature == _games_signature:
		return
	_games_signature = signature
	for child in games_box.get_children():
		child.queue_free()
	if Network.found_games.is_empty():
		_label(games_box, "  (procurando...)", 16)
	for ip in Network.found_games:
		var info: Dictionary = Network.found_games[ip]
		_button(games_box, "Entrar em %s  (%d/%d jogadores)" % [ip, info.players, Network.MAX_PLAYERS],
				func(): _join(ip))


func _on_class_pressed(id: String) -> void:
	Network.set_my_class(id)
	_refresh_class()


func _refresh_class() -> void:
	for id in class_buttons:
		class_buttons[id].set_pressed_no_signal(id == Network.my_class)
	class_description.text = Classes.info(Network.my_class).description


func _on_mode_pressed(id: String) -> void:
	Network.set_setting("mode", id)
	_refresh()


func _on_team_pressed(team: int) -> void:
	Network.set_my_team(team)
	_refresh()


# Modo, time e bots: o host (ou o menu, antes de hospedar) escolhe; os outros só veem.
func _refresh_options() -> void:
	var can_edit := state == State.MENU or state == State.HOSTING
	var moba := Network.game_mode() == "moba"
	for id in mode_buttons:
		mode_buttons[id].set_pressed_no_signal(id == Network.game_mode())
		mode_buttons[id].disabled = not can_edit
	team_row.visible = moba and (state == State.HOSTING or state == State.CONNECTED)
	var my_team := Network.team_of(multiplayer.get_unique_id())
	for team in team_buttons:
		team_buttons[team].set_pressed_no_signal(team == my_team)
	bots_check.visible = moba
	bots_check.disabled = not can_edit
	bots_check.set_pressed_no_signal(Network.settings.get("bots", true))


# "Host: Mago", "Jogador 2 (você): Lutador"... (no MOBA, com o time)
func _players_text() -> String:
	var names := PackedStringArray()
	var moba := Network.game_mode() == "moba"
	for i in Network.players.size():
		var peer: int = Network.players[i]
		var who := "Host" if peer == 1 else "Jogador %d" % (i + 1)
		if peer == multiplayer.get_unique_id():
			who += " (você)"
		var line := "%s: %s" % [who, Classes.info(Network.class_of(peer)).label]
		if moba:
			line += " — time %s" % Combat.TEAM_NAMES[Network.team_of(peer)]
		names.append(line)
	if moba and Network.settings.get("bots", true):
		names.append("+ %d bot(s) para completar os times" % Network.bot_plan().size())
	return "\n".join(names)


func _set_state(new_state: State) -> void:
	state = new_state
	menu_box.visible = state == State.MENU
	wait_box.visible = state != State.MENU
	start_button.visible = state == State.HOSTING
	_games_signature = "?"
	_refresh()


func _refresh() -> void:
	_refresh_options()
	if state == State.HOSTING:
		var lines := PackedStringArray(["Partida aberta! Seus amigos já devem vê-la na tela deles.", ""])
		for entry in Network.lan_addresses():
			lines.append("Seu IP (%s): %s" % [entry.name, entry.ip])
		lines.append("")
		lines.append("Jogadores conectados: %d/%d" % [Network.players.size(), Network.MAX_PLAYERS])
		lines.append(_players_text())
		wait_label.text = "\n".join(lines)
		if _autostart > 0 and Network.players.size() >= _autostart:
			_on_start_pressed.call_deferred()
	elif state == State.CONNECTING:
		wait_label.text = "Conectando..."
	elif state == State.CONNECTED:
		wait_label.text = "Conectado! Modo: %s\nJogadores: %d/%d\n%s\nAguardando o host começar a partida..." % [
			Network.MODES[Network.game_mode()], Network.players.size(), Network.MAX_PLAYERS, _players_text()]


func _on_host_pressed() -> void:
	if Network.host() != OK:
		status_label.text = "Não foi possível hospedar (a porta %d já está em uso?)." % Network.PORT
		return
	status_label.text = ""
	_set_state(State.HOSTING)


func _on_solo_pressed() -> void:
	if Network.host() == OK:
		Network.start_game()
	else:
		status_label.text = "Não foi possível iniciar (a porta %d já está em uso?)." % Network.PORT


func _join(address: String) -> void:
	address = address.strip_edges()
	if address.is_empty():
		status_label.text = "Digite o IP do host."
		return
	if Network.join(address) != OK:
		status_label.text = "Endereço inválido: %s" % address
		return
	status_label.text = ""
	_set_state(State.CONNECTING)


func _on_connection_failed() -> void:
	_set_state(State.MENU)
	status_label.text = "Não foi possível conectar. Confira o IP e se o host está com a partida aberta."


func _on_start_pressed() -> void:
	if state == State.HOSTING:
		Network.start_game()


func _on_cancel_pressed() -> void:
	Network.leave()
	_set_state(State.MENU)


func _parse_command_line() -> void:
	if Network.command_line_used:
		return
	Network.command_line_used = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autostart="):
			_autostart = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--class="):
			Network.set_my_class(arg.get_slice("=", 1))
			_refresh_class()
		elif arg.begins_with("--mode="):
			Network.set_setting("mode", arg.get_slice("=", 1))
			_refresh()
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host_pressed()
		elif arg == "--solo":
			_on_solo_pressed()
		elif arg.begins_with("--join="):
			_join(arg.get_slice("=", 1))


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
