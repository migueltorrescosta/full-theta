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
## The Host form's scenarios: the --encounter each passes, and the label key of each.
const SCENARIOS: Array[String] = ["run", "shakedown"]
const SCENARIO_KEYS: Array[String] = ["train.mode_run", "train.mode_shakedown"]
## How long a lesson's shell stays hidden while the server seats and starts it (ms).
const LESSON_WAIT_MS: int = 8000

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
## The single column (desktop, tablet, phone upright) and the two columns of a phone on its
## side (#28): the player's details left, the games to join right.
var _col: VBoxContainer
var _wide: HBoxContainer
var _scroll: ScrollContainer
var _wide_scroll: ScrollContainer
var _left: VBoxContainer
var _right: VBoxContainer
## The menu's rows in single-column order, each with its side in the two columns.
var _items: Array[Control] = []
var _item_right: Array[bool] = []
var _join_label: Label
var _join_row: HBoxContainer
var _bottom: HFlowContainer
## The Host form's row; null on the web.
var _host_row: HFlowContainer
var _name: LineEdit
var _bind: OptionButton
var _lang: OptionButton
var _dev: CheckBox
var _scenario: OptionButton
var _hosts: ItemList
var _address: LineEdit
var _status: Label
var _rejoin: Button
var _settings_screen: SettingsScreen
var _training: Button
var _picker: TrainingPicker
var _orphan_dialog: ConfirmationDialog
var _orphan_answer: HostSession.Answer = HostSession.Answer.LEAVE
## The station lesson being started or played (D303): `_lesson_on` while there is one, `_lesson`
## its station ("" is the crew drill), and what the picker should say when it comes back.
var _lesson_on: bool = false
var _lesson: String = ""
var _lesson_note: String = ""
## Until when a lesson's shell waits for the server to seat and start it (ms).
var _lesson_deadline: int = 0


func _ready() -> void:
	AlertTones.sounds_dir = ALERT_SOUNDS
	settings.load_file()
	I18n.apply(I18n.LANGUAGES[0])
	LayoutMode.apply(get_tree().root)
	_apply_scale()
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
			_lesson_failed()
	if joining != null:
		joining.poll()
		if joining.is_welcomed():
			_save_token(joining)
			_start_shell(joining)
			joining = null
		elif joining.state in [NetClient.State.REJECTED, NetClient.State.CLOSED]:
			_status.text = tr("menu.join_failed") % joining.reject_reason
			joining = null
			WebLoadStage.report(WebLoadStage.READY)
			_lesson_failed()
	if _lesson_on and shell != null and not shell.visible:
		_reveal_lesson_if_started()


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
func host(bind: String = "", scenario: String = "", solo: String = "") -> void:
	_remember_name()
	if bind == "":
		bind = bind_addresses()[_bind.selected]
	var o: HostSession.Options = HostSession.Options.new(bind)
	o.language = I18n.LANGUAGES[_lang.selected]
	o.dev_all = _dev.button_pressed and solo == ""
	o.encounter = scenario if scenario != "" else SCENARIOS[_scenario.selected]
	o.solo = solo
	host_session = HostSession.new(settings.player_name)
	host_session.token_file = token_path
	host_session.launcher.pid_file = pid_path
	if host_session.host(o) != OK:
		_status.text = tr("menu.host_failed") % host_session.error
		host_session = null
		_lesson_failed()
		return
	_status.text = tr("menu.starting")


## Join by a typed address (FT-NET-013) or a listed host's url.
func join(text: String) -> void:
	var addr: LanBrowser.Address = LanBrowser.parse_address(text)
	if not addr.ok:
		_status.text = addr.error
		WebLoadStage.report(WebLoadStage.READY)
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
	WebLoadStage.report(WebLoadStage.CONNECT)
	if joining.connect_to(url) != OK:
		_status.text = tr("menu.join_failed") % url
		joining = null
		WebLoadStage.report(WebLoadStage.READY)
		return
	_status.text = tr("menu.connecting")


func _save_token(c: NetClient) -> void:
	var addr: LanBrowser.Address = LanBrowser.parse_address(c.url.trim_prefix("ws://"))
	if addr.ok:
		SessionTokenFile.make(c.token, addr.host, addr.port).save(token_path)


func _start_shell(client: NetClient) -> void:
	WebLoadStage.report(WebLoadStage.LOBBY)
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
	if _lesson_on:
		_begin_lesson(client)


## The player left the session: the host also ends its server (FT-NET-003); a joined
## client forgets its token.
func _on_left() -> void:
	shell.queue_free()
	shell = null
	var was_lesson: bool = _lesson_on
	_lesson_on = false
	if host_session != null:
		_stop_host()
	else:
		SessionTokenFile.remove(token_path)
	_menu.visible = true
	_refresh_rejoin()
	_apply_scale()
	if was_lesson:
		_picker.refresh()
		_picker.show_note(_lesson_note)
		_picker.visible = true
		_lesson_note = ""


func _stop_host() -> void:
	if host_session != null:
		host_session.stop()
		host_session = null


func _remember_name() -> void:
	var n: String = _name.text.strip_edges()
	settings.player_name = n if n != "" else tr("menu.default_name")
	settings.save()


# --- Solo training (D303). ---


## Opens the Training picker: the first of the two taps to any lesson.
func open_training() -> void:
	_picker.refresh()
	_picker.show_note("")
	_picker.visible = true


## Starts the lesson of `station` ("" is the crew drill), the second tap. A desktop client
## hosts a local server that seats it at once (--solo); a browser asks the server it joins,
## which refuses when other players are on it.
func start_lesson(station: String) -> void:
	_remember_name()
	_lesson_on = true
	_lesson = station
	_lesson_note = ""
	_picker.show_note(tr("train.picker.starting"))
	_picker.set_busy(true)
	if web:
		var addr: LanBrowser.Address = LanBrowser.parse_address(_address.text)
		if not addr.ok:
			_lesson_failed()
			return
		_connect(addr.url, "")
	elif station == "":
		host("", "shakedown")  # the crew drill on the Host form's address: others may join
	else:
		host(LOOPBACK, "shakedown", station)


func _lesson_failed() -> void:
	if not _lesson_on:
		return
	_lesson_on = false
	_picker.show_note(tr("train.picker.failed"))


## The shell of a lesson stays hidden until the server has seated and started it; a browser
## asks for the lesson now that it is welcomed.
func _begin_lesson(client: NetClient) -> void:
	_lesson_deadline = Time.get_ticks_msec() + LESSON_WAIT_MS
	shell.voice.subtitle.connect(_on_lesson_line)
	if host_session != null and _lesson == "":
		return  # the crew drill hosted here opens on its lobby as usual
	shell.visible = false
	if host_session == null:
		client.event_received.connect(_on_lesson_event)
		client.start_training(_lesson)


func _on_lesson_event(e: Dictionary) -> void:
	var payload: Dictionary = e.get("payload", {})
	match str(e.get("type", "")):
		NetProtocol.EVENT_REQUEST_REJECTED:
			if int(payload.get("request", -1)) != NetProtocol.Type.TRAINING or shell == null:
				return
			if str(payload.get("reason", "")) == NetTraining.BUSY:
				var players: int = int(payload.get("players", 0))
				_lesson_note = (
					tr("train.picker.busy_one" if players == 1 else "train.picker.busy_many")
					% players
				)
			else:
				_lesson_note = tr("train.picker.failed")
			shell.leave()
		NetProtocol.EVENT_PICKED:
			if _lesson == "" and shell != null:
				_reveal_lesson()


## A station lesson shows once the crew state says the server seated and started it, or
## after LESSON_WAIT_MS.
func _reveal_lesson_if_started() -> void:
	var crew: CrewState = shell.ctx.crew
	var seated: bool = _lesson != "" and crew.entry == _lesson and crew.is_started()
	if seated or Time.get_ticks_msec() > _lesson_deadline:
		_reveal_lesson()


func _reveal_lesson() -> void:
	shell.visible = true
	_picker.visible = false
	_picker.show_note("")


## The Shakedown's last line ends the lesson: its station gets its tick.
func _on_lesson_line(entry: Dictionary) -> void:
	if _lesson == "" or str(entry.get("line", "")) != "shakedown.all_done":
		return
	settings.mark_lesson_done(_lesson)
	settings.save()
	_picker.refresh()


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
	else:
		WebLoadStage.report(WebLoadStage.READY)


# --- Layout. ---


## The window's content scale for a UI scale (FT-STN-013). A browser draws in canvas pixels,
## `density` (the capped devicePixelRatio) per CSS pixel, so on the web the UI scale is
## multiplied by it: a 48 px button stays 48 CSS px at dpr 2 (#28). Native windows keep the
## UI scale alone.
static func content_scale(ui_scale: float, on_web: bool, density: float) -> float:
	return ui_scale * (maxf(density, 1.0) if on_web else 1.0)


## Sets the window's content scale from the player's UI scale (and the browser's density).
func _apply_scale() -> void:
	var w: Window = get_tree().root
	var k: float = content_scale(settings.ui_scale, OS.has_feature("web"), LayoutMode.density())
	if not is_equal_approx(w.content_scale_factor, k):
		w.content_scale_factor = k


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
	_scroll = scroll
	var col: VBoxContainer = VBoxContainer.new()
	_col = col
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)
	_wide_scroll = ScrollContainer.new()
	_wide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_wide_scroll.visible = false
	_menu.add_child(_wide_scroll)
	_wide = HBoxContainer.new()
	_wide.name = "TwoColumns"
	_wide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wide.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wide_scroll.add_child(_wide)
	_wide.add_theme_constant_override("separation", 24)
	_left = VBoxContainer.new()
	_right = VBoxContainer.new()
	for c: VBoxContainer in [_left, _right]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 12)
		_wide.add_child(c)
	var title: Label = Label.new()
	title.text = "FULL THETA"
	title.theme_type_variation = "TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Full screen (D277, design 2.10) at the title's right where the browser offers it.
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	title_row.add_child(title)
	var fullscreen: FullscreenButton = FullscreenButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fullscreen.clip_text = false
	fullscreen.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	title_row.add_child(fullscreen)
	_item(col, title_row, false)
	_name = LineEdit.new()
	_name.name = "Name"
	_name.placeholder_text = tr("menu.name")
	_name.text = settings.player_name
	_item(col, _name, false)
	WebTextField.attach(_name)
	# A browser can't start a server; it joins the one that served the page.
	if not web:
		_build_host(col)
	_build_join(col)
	_bottom = HFlowContainer.new()
	var bottom: HFlowContainer = _bottom
	# Two columns: with the Host form on the left, the buttons and status go under Join.
	_item(col, bottom, not web)
	_training = _button(bottom, "Training", tr("menu.training"), open_training)
	_rejoin = _button(bottom, "Rejoin", tr("menu.rejoin"), rejoin)
	_button(bottom, "Settings", tr("menu.settings"), func() -> void: _settings_screen.open())
	_button(bottom, "Quit", tr("menu.quit"), quit)
	_status = Label.new()
	_status.name = "Status"
	_item(col, _status, not web)
	_settings_screen = SettingsScreen.new()
	_settings_screen.visible = false
	add_child(_settings_screen)
	_settings_screen.setup(settings, false)
	_settings_screen.scale_changed.connect(_apply_scale)
	_picker = TrainingPicker.new()
	_picker.visible = false
	add_child(_picker)
	_picker.setup(settings, load("res://content/training/steps.tres") as TrainingStepsDef)
	_picker.closed.connect(func() -> void: _picker.visible = false)
	_picker.chosen.connect(start_lesson)
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
	# The game's root is a full-rect Control, so the window's theme reaches the menu there;
	# a menu outside it (a test's SubViewport, a plain Node) would lose it: follow the
	# window's here (LayoutMode.apply re-sets it first on a resize).
	theme = get_window().theme
	_apply_scale()
	var phone: bool = LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	var margin: float = 16.0 if phone else 40.0
	# On a phone nothing sits under a notch or in the gesture band (#28, SafeArea).
	var m: Vector4 = SafeArea.margins(self)
	var band: float = SafeArea.tap_band(self)
	var sides: Array[float] = [
		maxf(margin, m.x + 8.0), maxf(margin, m.z + 8.0), maxf(margin, m.y), maxf(margin, band)
	]
	if not phone:
		sides = [margin, margin, margin, margin]
	for i: int in 4:
		_menu.add_theme_constant_override(
			"margin_" + ["left", "right", "top", "bottom"][i], roundi(sides[i])
		)
	# Phone buttons keep the 8 px gap of touch targets (#28).
	if phone:
		_bottom.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	else:
		_bottom.remove_theme_constant_override("h_separation")
	if _host_row != null:
		if phone:
			_host_row.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
		else:
			_host_row.remove_theme_constant_override("v_separation")
	_arrange(LayoutMode.form_of(self) == LayoutMode.Form.PHONE_LANDSCAPE)
	var wide: Control.SizeFlags = (
		(Control.SIZE_EXPAND_FILL if phone else Control.SIZE_SHRINK_BEGIN) as Control.SizeFlags
	)
	_name.size_flags_horizontal = wide
	_hosts.size_flags_horizontal = wide
	_join_row.size_flags_horizontal = wide
	_name.custom_minimum_size = Vector2(0 if phone else 320, 0)
	_hosts.custom_minimum_size = Vector2(0 if phone else 480, 120)
	_relayout_lists(_wide_scroll.visible)
	_address.custom_minimum_size = Vector2(0 if phone else 320, 0)


## A phone on its side shows two columns that fit without scrolling: the title, name, host
## form and buttons left, the games list, address and Join right (#28). Else one column.
func _arrange(two: bool) -> void:
	if two == _wide_scroll.visible:
		return
	_wide_scroll.visible = two
	_scroll.visible = not two
	for i: int in _items.size():
		var row: Control = _items[i]
		var to: VBoxContainer = _col
		if two:
			to = _right if _item_right[i] else _left
		row.get_parent().remove_child(row)
		to.add_child(row)
	_hosts.size_flags_vertical = Control.SIZE_EXPAND_FILL if two else Control.SIZE_FILL
	_relayout_lists(two)


## The games list takes the right column's free height in two columns.
func _relayout_lists(two: bool) -> void:
	_hosts.custom_minimum_size.y = 48.0 if two else 120.0


func _build_host(col: VBoxContainer) -> void:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	_host_row = row
	_item(col, row, false)
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
	# the scenario the server holds: the run, or the Shakedown (Q17 A).
	_scenario = OptionButton.new()
	_scenario.name = "Scenario"
	_scenario.tooltip_text = tr("train.mode")
	for key: String in SCENARIO_KEYS:
		_scenario.add_item(tr(key))
	row.add_child(_scenario)
	_dev = CheckBox.new()
	_dev.name = "DevAll"
	_dev.text = tr("menu.dev_all")
	row.add_child(_dev)
	_button(row, "Host", tr("menu.host"), host)


func _build_join(col: VBoxContainer) -> void:
	_join_label = _label(tr("menu.lan_games"))
	_item(col, _join_label, true)
	_hosts = ItemList.new()
	_hosts.name = "Hosts"
	ListLines.attach(_hosts)
	_hosts.item_activated.connect(
		func(i: int) -> void: _connect(str(_hosts.get_item_metadata(i)), "")
	)
	_item(col, _hosts, true)
	var row: HBoxContainer = HBoxContainer.new()
	_join_row = row
	_item(col, row, true)
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


## Adds one of the menu's rows to the single column, remembering its side in the two.
func _item(col: VBoxContainer, row: Control, right: bool) -> void:
	col.add_child(row)
	_items.append(row)
	_item_right.append(right)


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
