class_name ClientShell
extends Control
## The station shell (T049, FT-ARC-015): takes a welcomed NetClient from the main menu
## and runs the session: polls it every frame, feeds every event to the VoicePlayer
## (voice lines, audio/README.md "Client") or the CrewState model, records snapshots in
## the SnapshotInterpolator, and shows the lobby until the pick's ship has started,
## then the StationScreen of the pick, with the pause overlay, the outcome card (D178),
## subtitles and the menu (Settings and Controls, D185) on top. It resumes a dropped
## connection with its token
## (FT-NET-025) and goes back to the lobby when the server resets the run (FT-M1-012).
##
## Multi-ship sessions (#11): a session handed over to the scoreboard (no friendly ship
## left, D91) or in a PvP session that is over shows the ScoreboardScreen; a handover to a
## friendly ship's main screen shows the HandoverNotice over it; the give-up (forfeit) and
## relaunch votes show as VotePrompts; the menu confirms the host's abandon or give-up in
## place, since it takes the ship out of play at once.
##
## Load (#28, owner L-Keep): a station screen, once built, is kept (hidden, not processing,
## its alert tones detached) and shown again at once on the next visit of that pick; the
## least recently shown goes past MAX_SCREENS, and all go on a run reset, a language
## change, a new session or when the shell leaves. A first visit shows a loading overlay
## for one frame before it builds, so it draws, and keeps it until the new screen has run
## its first frame. A resume with the same pick keeps the
## screen. While the lobby shows, the pick's panel scripts load (one a frame), then the
## shared ship model builds in slices (ProceduralShip.warm). Frames over LONG_FRAME_US go
## to the server's session log with what was running (NetClient.report_frame).

## The player left (Settings > Leave); the menu takes over again.
signal left

## The crew changes that may switch between the lobby, a station and the scoreboard.
const SCREEN_KINDS: Array[StringName] = [
	&"picked",
	&"lobby",
	&"started",
	&"reset",
	&"catalogue",
	&"fleet",
	&"handover",
	&"session_over",
	&"relaunch",
]
## Retry a dropped connection this often (ms).
const RESUME_MS: int = 2000
## Station screens kept at most; the dev seat's holds all six panels.
const MAX_SCREENS: int = 4
## A frame longer than this (µs) is reported to the server.
const LONG_FRAME_US: int = 500_000
## Lobby warm-up per frame (µs) for the ship model.
const WARM_BUDGET_US: int = 8000
## The ship model's wears to warm: HelmView's, then SpaceView's.
const SHIP_WEARS: Array[float] = [1.0, 0.6]
## Strand T's tips (shown on the loading overlay when the file exists).
const TIPS_VIEW: String = "res://presentation/tips_view.gd"

var ctx: StationContext = StationContext.new()
var voice: VoicePlayer
var lobby: LobbyScreen
var screen: StationScreen
var pause_overlay: PauseOverlay
var outcome_card: OutcomeCard
var settings_screen: SettingsScreen
var scoreboard: ScoreboardScreen
var handover_notice: HandoverNotice
var forfeit_prompt: VotePrompt
var relaunch_prompt: VotePrompt

var _layer: Control
var _banner: Label
var _subtitles: Label
var _last_seq: int = -1
var _shown: String = ""
var _resume_at: int = 0
## The Welcome dictionary last applied (NetClient makes a new one per Welcome).
var _welcome: Dictionary = {}
## Built station screens by pick key ("station:<ship>:<entry>"), least recently shown first.
var _screens: Dictionary = {}
## A hidden screen -> its StationAlerts' crew connections ([signal, callable] pairs).
var _detached: Dictionary = {}
## The loading overlay of a first visit, and its station name.
var _loading: Control
var _loading_name: Label
## The pick key waiting to build, and the frame its overlay was shown on.
var _pending: String = ""
var _pending_frame: int = 0
## The session language and locale last applied.
var _lang: String = ""
var _locale: String = ""
## Panel scripts loaded in the lobby (kept, so they stay cached).
var _scripts: Dictionary = {}
## What this frame did (for a long frame's report), when the last frame started (µs), and
## whether the window lost focus since.
var _doing: String = ""
var _frame_us: int = 0
var _away: bool = false


## Starts the session on a welcomed client. The host passes its server's address and
## WebSocket port for the lobby's join info.
func setup(
	client: NetClient, settings: ClientSettings, host_bind: String = "", host_port: int = 0
) -> void:
	ctx.client = client
	ctx.host_bind = host_bind
	ctx.host_port = host_port
	ctx.intents = ShipIntents.new(client)
	ctx.settings = settings
	ctx.matcher = InputMatcher.new(settings.bindings)
	ctx.matcher.invert_pitch = settings.invert_pitch
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voice = VoicePlayer.new()
	add_child(voice)
	voice.subtitle.connect(func(_entry: Dictionary) -> void: _show_subtitles())
	voice.subtitle.connect(_note_training)
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	_build_loading()
	_build_overlays()
	_on_welcome()
	ctx.crew.changed.connect(_on_crew_changed)
	apply_ui_scale()


## The UI scale setting (FT-STN-013) as the window's content scale. A browser draws in
## canvas pixels, devicePixelRatio (capped) per CSS pixel, so on the web the scale is
## multiplied by it: a 48 px button stays 48 CSS px at dpr 2 (#28, MainMenu.content_scale).
func apply_ui_scale() -> void:
	if is_inside_tree():
		var dpr: float = maxf(LayoutMode.density(), 1.0) if OS.has_feature("web") else 1.0
		get_tree().root.content_scale_factor = ctx.settings.ui_scale * dpr


func _ready() -> void:
	apply_ui_scale()


func _process(_delta: float) -> void:
	_check_frame()
	var client: NetClient = ctx.client
	var now: int = ctx.now_ms()
	client.poll()
	voice.pump(client)
	if client.state == NetClient.State.CLOSED and now >= _resume_at:
		_resume_at = now + RESUME_MS
		client.resume()
	_banner.visible = client.state != NetClient.State.WELCOMED
	_banner.text = tr("shell.reconnecting")
	if client.is_welcomed() and not is_same(client.welcome, _welcome):
		_on_welcome()
	if not is_same(ctx.crew.catalogue, client.catalogue) and not client.catalogue.is_empty():
		ctx.crew.set_catalogue(client.catalogue)
	for e: Dictionary in client.take_events():
		if not voice.handle_event(e):
			ctx.crew.handle_event(e, now)
	ctx.view = client.view
	if ctx.view.seq != _last_seq and ctx.view.seq >= 0:
		_last_seq = ctx.view.seq
		ctx.interp.push(ctx.view, now)
	ctx.interp.update(now)
	_show_subtitles()
	if _loading.visible and _pending == "":
		# The new screen has run its first frame: it draws filled in.
		_loading.visible = false
	if _pending != "" and Engine.get_process_frames() > _pending_frame:
		_build_pending()
	elif lobby != null:
		_warm_step()


## Leaves the session: Bye, then `left`.
func leave() -> void:
	if ctx.client.is_welcomed():
		ctx.client.bye()
	left.emit()


## Welcome (first or after a resume): pick, session language for UI text, subtitles and
## prerendered lines (FT-AUD-013). A resume of the same session with the same pick and
## language keeps the screen as it is (load fix 3, #28); a new session drops the kept
## screens.
func _on_welcome() -> void:
	_note("welcome")
	var w: Dictionary = ctx.client.welcome
	if not _welcome.is_empty() and int(w.get("session", -1)) != int(_welcome.get("session", -1)):
		_drop_screens()
	_welcome = w
	ctx.crew.welcome(w)
	var lang: String = str(w.get("lang", "en"))
	if lang != _lang:
		_lang = lang
		I18n.apply(lang)
		voice.local_lines = LocalLines.new(lang)
	_locale = TranslationServer.get_locale()
	ctx.interp = SnapshotInterpolator.new()
	_last_seq = -1
	_on_crew_changed(&"picked")


## A language switch rebuilds the open lobby or station screen in the new language and
## drops the kept ones (the menu retranslates itself). A long gap after the window lost
## focus is marked in its report.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_away = true
	if what != NOTIFICATION_TRANSLATION_CHANGED or ctx == null or _shown == "":
		return
	if TranslationServer.get_locale() == _locale:
		return
	_locale = TranslationServer.get_locale()
	_drop_screens()
	_shown = ""
	_on_crew_changed(&"picked")


func _on_crew_changed(what: StringName) -> void:
	if what == &"reset":
		_drop_screens()
	if what not in SCREEN_KINDS:
		return
	var want: String = (
		"lobby"
		if ctx.crew.entry == "" or not ctx.crew.is_started() or ctx.crew.catalogue.is_empty()
		else "station:%d:%s" % [ctx.crew.ship, ctx.crew.entry]
	)
	if ctx.crew.on_scoreboard():
		want = "scoreboard"
	if want == _shown:
		return
	_shown = want
	_note("show " + want)
	if screen != null:
		_hide(screen)
	screen = null
	for n: Control in [lobby, scoreboard]:
		if n != null:
			_layer.remove_child(n)
			n.queue_free()
	lobby = null
	scoreboard = null
	_pending = ""
	_loading.visible = false
	if want == "scoreboard":
		scoreboard = ScoreboardScreen.new()
		scoreboard.setup(ctx)
		scoreboard.menu_requested.connect(leave)
		_layer.add_child(scoreboard)
	elif want == "lobby":
		lobby = LobbyScreen.new()
		lobby.setup(ctx)
		lobby.menu_requested.connect(leave)
		_layer.add_child(lobby)
	elif _screens.has(want):
		_reveal(want)
	else:
		# The overlay draws this frame; the screen builds on the next.
		_pending = want
		_pending_frame = Engine.get_process_frames()
		_loading_name.text = tr("station." + ctx.crew.entry)
		_loading.visible = true


## Builds the pending pick's screen and keeps it.
func _build_pending() -> void:
	var key: String = _pending
	_pending = ""
	_note("build " + key)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	s.blockers = [settings_screen, outcome_card]
	s.menu_requested.connect(settings_screen.open)
	s.help_requested.connect(_toggle_help)
	# `screen` first: entering the tree may ask for the first-visit help.
	screen = s
	_screens[key] = s
	_layer.add_child(s)
	while _screens.size() > MAX_SCREENS:
		_free_screen(_screens.keys()[0])


## Shows the kept screen of `key` again, as it was left; the matcher takes its stations and
## block state back.
func _reveal(key: String) -> void:
	var s: StationScreen = _screens[key]
	_screens.erase(key)
	_screens[key] = s
	for link: Array in _detached.get(s, []):
		ctx.crew.connect(link[0], link[1])
	_detached.erase(s)
	s.visible = true
	s.process_mode = Node.PROCESS_MODE_INHERIT
	ctx.matcher.restrict(StationScreen.UNBLOCKED if s.blocked() else [])
	s.focus(s.focus_index)
	screen = s


## Hides a kept screen: it stops processing and input, and its alerts stop listening, so a
## hidden screen never sounds a tone.
func _hide(s: StationScreen) -> void:
	s.release_all()
	s.visible = false
	s.process_mode = Node.PROCESS_MODE_DISABLED
	var links: Array = []
	for sig: StringName in [&"sim_event", &"pinged", &"changed", &"toast"]:
		for c: Dictionary in ctx.crew.get_signal_connection_list(sig):
			var callable: Callable = c["callable"]
			var target: Node = callable.get_object() as Node
			if target != null and (target == s.alerts or s.alerts.is_ancestor_of(target)):
				ctx.crew.disconnect(sig, callable)
				links.append([sig, callable])
	_detached[s] = links


func _free_screen(key: String) -> void:
	var s: StationScreen = _screens[key]
	_screens.erase(key)
	_detached.erase(s)
	if s == screen:
		screen = null
	_layer.remove_child(s)
	s.queue_free()


## Frees every kept station screen (a run reset, a language change, a new session).
func _drop_screens() -> void:
	for key: String in _screens.keys():
		_free_screen(key)
	_pending = ""
	if _shown.begins_with("station:"):
		_shown = ""


## One lobby frame's warm-up: the pick's next panel script, else a slice of the shared
## ship model (load fix 7, #28).
func _warm_step() -> void:
	var stations: Array = ctx.crew.stations()
	if stations.is_empty() and ctx.crew.entry != "":
		stations = [ctx.crew.entry]
	for station: Variant in stations:
		var path: String = StationRegistry.PANELS.get(str(station), "")
		if path != "" and not _scripts.has(path):
			_note("preload " + str(station))
			_scripts[path] = load(path)
			return
	for wear: float in SHIP_WEARS:
		if not ProceduralShip.warm(wear, WARM_BUDGET_US):
			_note("warm ship")
			return


## Adds a step to what this frame did.
func _note(step: String) -> void:
	_doing = step if _doing == "" else "%s, %s" % [_doing, step]


## Reports the last frame to the server when it took longer than LONG_FRAME_US (load fix
## 10, #28): its length and what ran (this shell's step, the screen, the menu's tab).
func _check_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _frame_us > 0 and now - _frame_us > LONG_FRAME_US and ctx.client.is_welcomed():
		var what: String = "%s on %s" % [_doing if _doing != "" else "frame", _shown]
		if settings_screen.visible:
			what += ", menu " + settings_screen.current_tab_name()
		if _away:
			what += ", away"
		ctx.client.report_frame(int((now - _frame_us) / 1000), what)
	_frame_us = now
	_doing = ""
	_away = false


## The first visit's loading overlay: the station's name over the background (and strand
## T's tips once they exist).
func _build_loading() -> void:
	_loading = Control.new()
	_loading.name = "Loading"
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	_loading_name = Label.new()
	_loading_name.theme_type_variation = "TitleLabel"
	_loading_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_name.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(_loading_name)
	if ResourceLoader.exists(TIPS_VIEW):
		var tips: Control = (load(TIPS_VIEW) as GDScript).new() as Control
		if tips != null:
			tips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_loading.add_child(tips)
	add_child(_loading)


func _show_subtitles() -> void:
	var lines: PackedStringArray = []
	for e: Dictionary in voice.subtitles.active(ctx.now_ms()):
		# a line's binding slot shows the player's current binding.
		var text: String = BindingText.fill_markers(
			str(e["text"]), ctx.settings.bindings, ctx.matcher.device
		)
		lines.append("%s: %s" % [tr(str(e["label_key"])), text])
	_subtitles.text = "\n".join(lines)


## Keeps the Shakedown's latest step per station for the banner (TrainingBanner).
func _note_training(entry: Dictionary) -> void:
	TrainingBanner.note(ctx.training, entry, _pair_stations)


## The two stations of a pair step line ("pair_p3").
func _pair_stations(pair_id: String) -> Array:
	var steps: TrainingStepsDef = load("res://content/training/steps.tres") as TrainingStepsDef
	if steps != null:
		for s: TrainingStepDef in steps.pairs():
			if s.intent == StringName(pair_id):
				return [String(s.station), String(s.partner)]
	return []


## `?`, View, or a first visit: the menu on Controls for this screen's stations; the
## same key again closes it.
func _toggle_help() -> void:
	_note("help")
	var menu: SettingsScreen = settings_screen
	if menu.visible and menu.current_tab_name() == SettingsScreen.TAB_CONTROLS:
		menu.close()
		return
	menu.set_controls(ctx.settings.bindings, screen.stations, ctx.matcher.device, ctx.crew.entry)
	menu.open(SettingsScreen.TAB_CONTROLS)


## The menu's abandon (co-op) or give-up (PvP) control: a crew player's vote, which they can
## take back; the host's ends the ship's run at once (the menu has confirmed it).
func request_abandon() -> void:
	if ctx.crew.host:
		ctx.intents.abandon(ctx.crew.ship)
	else:
		ctx.intents.vote_abandon(ctx.crew.ship, not ctx.crew.has_abandon_vote())


func _build_fleet_overlays() -> void:
	handover_notice = HandoverNotice.new()
	handover_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	handover_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	handover_notice.position.y += 64
	add_child(handover_notice)
	handover_notice.setup(ctx)
	forfeit_prompt = VotePrompt.new()
	add_child(forfeit_prompt)
	forfeit_prompt.setup(ctx, VotePrompt.Kind.FORFEIT)
	relaunch_prompt = VotePrompt.new()
	add_child(relaunch_prompt)
	relaunch_prompt.setup(ctx, VotePrompt.Kind.RELAUNCH)


func _build_overlays() -> void:
	pause_overlay = PauseOverlay.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(pause_overlay)
	pause_overlay.setup(ctx)
	outcome_card = OutcomeCard.new()
	outcome_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	outcome_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	outcome_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(outcome_card)
	outcome_card.setup(ctx)
	_build_fleet_overlays()
	_banner = Label.new()
	_banner.theme_type_variation = "TitleLabel"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y += 80
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_subtitles = Label.new()
	_subtitles.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitles.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitles.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitles.position.y -= 24
	_subtitles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitles)
	settings_screen = SettingsScreen.new()
	settings_screen.visible = false
	add_child(settings_screen)
	settings_screen.setup(ctx.settings, true)
	settings_screen.leave_requested.connect(leave)
	settings_screen.host_pause_requested.connect(func() -> void: ctx.intents.host_pause(true))
	settings_screen.abandon_requested.connect(request_abandon)
	ctx.crew.changed.connect(
		func(_what: StringName) -> void:
			settings_screen.set_pause_control(ctx.crew.can_host_pause())
			settings_screen.set_abandon_control(ctx.crew.abandon_control())
			settings_screen.set_ship_name(ctx.crew.ship_name())
	)
	settings_screen.set_pause_control(ctx.crew.can_host_pause())
	settings_screen.set_abandon_control(ctx.crew.abandon_control())
	settings_screen.set_ship_name(ctx.crew.ship_name())
	settings_screen.scale_changed.connect(apply_ui_scale)
	settings_screen.closed.connect(
		func() -> void: ctx.matcher.invert_pitch = ctx.settings.invert_pitch
	)
	settings_screen.reference_plane_requested.connect(
		func() -> void: ctx.settings.reference_plane = ctx.interp.own_rotation()
	)
