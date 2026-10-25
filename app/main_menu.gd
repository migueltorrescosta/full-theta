class_name MainMenu
extends Control
## The client's main menu (T049, FT-NET-001, FT-NET-003, FT-NET-012/013):
## Name (persisted), Host (bind "This computer only" or a LAN address, session language,
## the dev "one client holds all stations" flag), Join (live LAN list, or a typed
## address through LanBrowser.parse_address), Rejoin (stored token), Settings, Quit.
## On start it runs HostSession.check_orphan and asks about an orphaned server with a
## session (rejoin, terminate or leave it). Once a client is welcomed it hands it to the
## ClientShell (stations/) and comes back when the player leaves. In app/ because only
## app/ may name HostSession.

const LOOPBACK: String = "127.0.0.1"
## The alert tones (AlertTones.sounds_dir; audio/ may not name assets/, spec §2.2).
const ALERT_SOUNDS: String = "res://assets/sounds/alerts"

var settings: ClientSettings = ClientSettings.new()
## Paths injectable for tests.
var token_path: String = SessionTokenFile.PATH
var pid_path: String = ServerPidFile.PATH
## The session this client hosts, or null.
var host_session: HostSession = null
## A joining client before its Welcome, or null.
var joining: NetClient = null
var shell: ClientShell = null
var browser: LanBrowser = LanBrowser.new(NetProtocol.PROTOCOL_VERSION)

## A browser client: no Host section, it joins the server that served the page. Tests
## and L5 shots set it to draw the browser's menu.
var web: bool = OS.has_feature("web")

var _menu: MarginContainer
var _join_row: HBoxContainer
var _name: LineEdit
var _bind: OptionButton
var _lang: OptionButton
var _dev: CheckBox
var _hosts: ItemList
var _address: LineEdit
var _status: Label
var _rejoin: Button
var _settings_screen: SettingsScreen
var _orphan_dialog: ConfirmationDialog
var _orphan_answer: HostSession.Answer = HostSession.Answer.LEAVE


func _ready() -> void:
	AlertTones.sounds_dir = ALERT_SOUNDS
	settings.load_file()
	I18n.apply(I18n.LANGUAGES[0])
	LayoutMode.apply(get_tree().root)
	get_tree().root.content_scale_factor = settings.ui_scale
	_build()
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	browser.start()
	_check_orphan.call_deferred()
	_apply_web_join_config()


func _process(_delta: float) -> void:
	# No LAN polling while the shell is up; the list redraws only when it changed.
	if shell == null and browser.poll(Time.get_ticks_usec()):
		_refresh_hosts()
	if host_session != null and shell == null:
		host_session.poll()
		if host_session.is_joined():
			_start_shell(host_session.client)
		elif host_session.state == HostSession.State.FAILED:
			_status.text = tr("menu.host_failed") % host_session.error
			host_session.stop()
			host_session = null
	if joining != null:
		joining.poll()
		if joining.is_welcomed():
			_save_token(joining)
			_start_shell(joining)
			joining = null
		elif joining.state in [NetClient.State.REJECTED, NetClient.State.CLOSED]:
			_status.text = tr("menu.join_failed") % joining.reject_reason
			joining = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


## The bind choices: loopback ("This computer only") then this machine's IPv4 LAN
## addresses (D108: never every interface by default).
static func bind_addresses() -> PackedStringArray:
	var out: PackedStringArray = [LOOPBACK]
	for a: String in IP.get_local_addresses():
		if a.is_valid_ip_address() and not a.contains(":") and not a.begins_with("127."):
			out.append(a)
	return out


## Host: spawns the server child and joins it as the host (FT-M1-002), bound to the
## chosen address, or to `bind` when given (ClientAutopilot).
func host(bind: String = "") -> void:
	_remember_name()
	if bind == "":
		bind = bind_addresses()[_bind.selected]
	var o: HostSession.Options = HostSession.Options.new(bind)
	o.language = I18n.LANGUAGES[_lang.selected]
	o.dev_all = _dev.button_pressed
	host_session = HostSession.new(settings.player_name)
	host_session.token_file = token_path
	host_session.launcher.pid_file = pid_path
	if host_session.host(o) != OK:
		_status.text = tr("menu.host_failed") % host_session.error
		host_session = null
		return
	_status.text = tr("menu.starting")


## Join by a typed address (FT-NET-013) or a listed host's url.
func join(text: String) -> void:
	var addr: LanBrowser.Address = LanBrowser.parse_address(text)
	if not addr.ok:
		_status.text = addr.error
		return
	settings.last_address = text
	_connect(addr.url, "")


## Rejoin with the stored token after a relaunch (FT-NET-003, FT-NET-025).
func rejoin() -> void:
	var t: SessionTokenFile = SessionTokenFile.load_from(token_path)
	if t != null:
		_connect(LanBrowser.ws_url(t.host, t.port), t.token)


func quit() -> void:
	if shell != null:
		shell.leave()
	_stop_host()
	settings.save()
	browser.stop()
	get_tree().quit()


func _connect(url: String, token: String) -> void:
	_remember_name()
	joining = NetClient.new()
	joining.name = settings.player_name
	joining.client_kind = "web" if OS.has_feature("web") else "desktop"
	joining.user_agent = WebPage.user_agent()
	if OS.has_feature("web"):
		joining.inbound_buffer_size = 1 << 20  # D108
	joining.token = token
	if joining.connect_to(url) != OK:
		_status.text = tr("menu.join_failed") % url
		joining = null
		return
	_status.text = tr("menu.connecting")


func _save_token(c: NetClient) -> void:
	var addr: LanBrowser.Address = LanBrowser.parse_address(c.url.trim_prefix("ws://"))
	if addr.ok:
		SessionTokenFile.make(c.token, addr.host, addr.port).save(token_path)


func _start_shell(client: NetClient) -> void:
	shell = ClientShell.new()
	add_child(shell)
	if host_session != null:
		shell.setup(client, settings, host_session.launcher.bind, host_session.launcher.port)
	else:
		shell.setup(client, settings)
	WebSession.attach(shell)
	shell.left.connect(_on_left)
	_menu.visible = false
	_status.text = ""


## The player left the session: the host also ends its server (FT-NET-003); a joined
## client forgets its token.
func _on_left() -> void:
	shell.queue_free()
	shell = null
	if host_session != null:
		_stop_host()
	else:
		SessionTokenFile.remove(token_path)
	_menu.visible = true
	_refresh_rejoin()
	get_tree().root.content_scale_factor = settings.ui_scale


func _stop_host() -> void:
	if host_session != null:
		host_session.stop()
		host_session = null


func _remember_name() -> void:
	var n: String = _name.text.strip_edges()
	settings.player_name = n if n != "" else tr("menu.default_name")
	settings.save()


# --- Orphan server on start (FT-NET-003, TECH-8). ---


## check_orphan asks synchronously, so it runs twice: first to learn whether there is a
## question (answering "leave" changes nothing), then with the player's answer.
func _check_orphan() -> void:
	var asked: Array = []
	var probe: Callable = func(check: OrphanCheck) -> HostSession.Answer:
		asked.append(check)
		return HostSession.Answer.LEAVE
	HostSession.check_orphan(probe, pid_path, token_path)
	_refresh_rejoin()
	if asked.is_empty():
		return
	var check: OrphanCheck = asked[0]
	_orphan_dialog.dialog_text = tr("menu.orphan_text")
	_orphan_dialog.get_ok_button().visible = check.action == OrphanCheck.Action.OFFER_REJOIN
	_orphan_dialog.popup_centered()


func _answer_orphan(answer: HostSession.Answer) -> void:
	_orphan_answer = answer
	_orphan_dialog.hide()
	var s: HostSession = HostSession.check_orphan(
		func(_c: OrphanCheck) -> HostSession.Answer: return _orphan_answer, pid_path, token_path
	)
	if s != null:
		host_session = s
		_status.text = tr("menu.connecting")
	_refresh_rejoin()


## A browser station joins the host that served its page without typing (D196, FT-NET-013):
## the address field is pre-filled and, unless the page has ?join=0, joined at once.
func _apply_web_join_config() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.web_config()
	if cfg.address.is_empty():
		return
	_address.text = cfg.address
	if cfg.auto_join:
		join(cfg.address)


# --- Layout. ---


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_menu = MarginContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	# A short screen (a phone on its side) scrolls the menu.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)
	var title: Label = Label.new()
	title.text = "FULL THETA"
	title.theme_type_variation = "TitleLabel"
	col.add_child(title)
	_name = LineEdit.new()
	_name.name = "Name"
	_name.placeholder_text = tr("menu.name")
	_name.text = settings.player_name
	col.add_child(_name)
	WebTextField.attach(_name)
	# A browser can't start a server; it joins the one that served the page.
	if not web:
		_build_host(col)
	_build_join(col)
	var bottom: HFlowContainer = HFlowContainer.new()
	col.add_child(bottom)
	_rejoin = _button(bottom, "Rejoin", tr("menu.rejoin"), rejoin)
	_button(bottom, "Settings", tr("menu.settings"), func() -> void: _settings_screen.open())
	_button(bottom, "Quit", tr("menu.quit"), quit)
	_status = Label.new()
	_status.name = "Status"
	col.add_child(_status)
	_settings_screen = SettingsScreen.new()
	_settings_screen.visible = false
	add_child(_settings_screen)
	_settings_screen.setup(settings, false)
	_settings_screen.scale_changed.connect(
		func() -> void: get_tree().root.content_scale_factor = settings.ui_scale
	)
	_orphan_dialog = ConfirmationDialog.new()
	_orphan_dialog.title = tr("menu.orphan_title")
	_orphan_dialog.ok_button_text = tr("menu.orphan_rejoin")
	_orphan_dialog.cancel_button_text = tr("menu.orphan_leave")
	_orphan_dialog.add_button(tr("menu.orphan_terminate"), true, "terminate")
	_orphan_dialog.confirmed.connect(_answer_orphan.bind(HostSession.Answer.REJOIN))
	_orphan_dialog.canceled.connect(_answer_orphan.bind(HostSession.Answer.LEAVE))
	_orphan_dialog.custom_action.connect(
		func(_a: StringName) -> void: _answer_orphan(HostSession.Answer.TERMINATE)
	)
	add_child(_orphan_dialog)


## Sizes the menu for the viewport (LayoutMode): wide fields and tight margins on a phone
## (D195), the fixed field widths of a desktop window otherwise. Runs on every resize.
func _relayout() -> void:
	var phone: bool = LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	var margin: int = 16 if phone else 40
	for side: String in ["left", "right", "top", "bottom"]:
		_menu.add_theme_constant_override("margin_" + side, margin)
	var wide: Control.SizeFlags = (
		(Control.SIZE_EXPAND_FILL if phone else Control.SIZE_SHRINK_BEGIN) as Control.SizeFlags
	)
	_name.size_flags_horizontal = wide
	_hosts.size_flags_horizontal = wide
	_join_row.size_flags_horizontal = wide
	_name.custom_minimum_size = Vector2(0 if phone else 320, 0)
	_hosts.custom_minimum_size = Vector2(0 if phone else 480, 120)
	_address.custom_minimum_size = Vector2(0 if phone else 320, 0)


func _build_host(col: VBoxContainer) -> void:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	col.add_child(row)
	_bind = OptionButton.new()
	_bind.name = "Bind"
	for a: String in bind_addresses():
		_bind.add_item(tr("menu.this_computer") if a == LOOPBACK else a)
	row.add_child(_bind)
	_lang = OptionButton.new()
	_lang.name = "Language"
	for l: String in I18n.LANGUAGES:
		_lang.add_item(tr("language." + l))
	row.add_child(_lang)
	_dev = CheckBox.new()
	_dev.name = "DevAll"
	_dev.text = tr("menu.dev_all")
	row.add_child(_dev)
	_button(row, "Host", tr("menu.host"), host)


func _build_join(col: VBoxContainer) -> void:
	col.add_child(_label(tr("menu.lan_games")))
	_hosts = ItemList.new()
	_hosts.name = "Hosts"
	_hosts.item_activated.connect(
		func(i: int) -> void: _connect(str(_hosts.get_item_metadata(i)), "")
	)
	col.add_child(_hosts)
	var row: HBoxContainer = HBoxContainer.new()
	_join_row = row
	col.add_child(row)
	_address = LineEdit.new()
	_address.name = "Address"
	_address.placeholder_text = tr("menu.address")
	_address.text = settings.last_address
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.virtual_keyboard_enabled = true
	_address.text_submitted.connect(join)
	row.add_child(_address)
	WebTextField.attach(_address)
	_button(row, "Join", tr("menu.join"), func() -> void: join(_address.text))


func _refresh_hosts() -> void:
	_hosts.clear()
	for h: LanBrowser.Host in browser.hosts():
		var text: String = "%s  %s  %d/%d" % [h.name, h.address, h.players, h.cap]
		if not h.compatible:
			text += "  " + tr("menu.incompatible")
		var i: int = _hosts.add_item(text)
		_hosts.set_item_metadata(i, h.url())
		_hosts.set_item_disabled(i, not h.compatible)


func _refresh_rejoin() -> void:
	var t: SessionTokenFile = SessionTokenFile.load_from(token_path)
	_rejoin.visible = t != null and t.host_secret == ""


func _label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	return l


func _button(parent: Node, node_name: String, text: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
