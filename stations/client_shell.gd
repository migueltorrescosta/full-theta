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

## The player left (Settings > Leave); the menu takes over again.
signal left

## Retry a dropped connection this often (ms).
const RESUME_MS: int = 2000

var ctx: StationContext = StationContext.new()
var voice: VoicePlayer
var lobby: LobbyScreen
var screen: StationScreen
var pause_overlay: PauseOverlay
var outcome_card: OutcomeCard
var settings_screen: SettingsScreen

var _layer: Control
var _banner: Label
var _subtitles: Label
var _last_seq: int = -1
var _shown: String = ""
var _resume_at: int = 0
## The Welcome dictionary last applied (NetClient makes a new one per Welcome).
var _welcome: Dictionary = {}


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
	_build_overlays()
	_on_welcome()
	ctx.crew.changed.connect(_on_crew_changed)
	apply_ui_scale()


## The UI scale setting (FT-STN-013) as the window's content scale.
func apply_ui_scale() -> void:
	if is_inside_tree():
		get_tree().root.content_scale_factor = ctx.settings.ui_scale


func _ready() -> void:
	apply_ui_scale()


func _process(_delta: float) -> void:
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


## Leaves the session: Bye, then `left`.
func leave() -> void:
	if ctx.client.is_welcomed():
		ctx.client.bye()
	left.emit()


## Welcome (first or after a resume): pick, session language for UI text, subtitles and
## prerendered lines (FT-AUD-013).
func _on_welcome() -> void:
	var w: Dictionary = ctx.client.welcome
	_welcome = w
	ctx.crew.welcome(w)
	var lang: String = str(w.get("lang", "en"))
	I18n.apply(lang)
	voice.local_lines = LocalLines.new(lang)
	ctx.interp = SnapshotInterpolator.new()
	_last_seq = -1
	_shown = ""
	_on_crew_changed(&"picked")


## A language switch rebuilds the open lobby or station screen in the new language (the
## menu retranslates itself).
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or ctx == null or _shown == "":
		return
	_shown = ""
	_on_crew_changed(&"picked")


func _on_crew_changed(what: StringName) -> void:
	if what not in [&"picked", &"lobby", &"started", &"reset", &"catalogue"]:
		return
	var want: String = (
		"lobby"
		if ctx.crew.entry == "" or not ctx.crew.is_started() or ctx.crew.catalogue.is_empty()
		else "station:%d:%s" % [ctx.crew.ship, ctx.crew.entry]
	)
	if want == _shown:
		return
	_shown = want
	for c: Node in _layer.get_children():
		_layer.remove_child(c)
		c.queue_free()
	screen = null
	lobby = null
	if want == "lobby":
		lobby = LobbyScreen.new()
		lobby.setup(ctx)
		lobby.menu_requested.connect(leave)
		_layer.add_child(lobby)
	else:
		screen = StationScreen.new()
		screen.setup(ctx)
		screen.blockers = [settings_screen, outcome_card]
		screen.menu_requested.connect(settings_screen.open)
		screen.help_requested.connect(_toggle_help)
		_layer.add_child(screen)


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
	var menu: SettingsScreen = settings_screen
	if menu.visible and menu.current_tab_name() == SettingsScreen.TAB_CONTROLS:
		menu.close()
		return
	menu.set_controls(ctx.settings.bindings, screen.stations, ctx.matcher.device, ctx.crew.entry)
	menu.open(SettingsScreen.TAB_CONTROLS)


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
	ctx.crew.changed.connect(
		func(_what: StringName) -> void:
			settings_screen.set_pause_control(ctx.crew.can_host_pause())
	)
	settings_screen.set_pause_control(ctx.crew.can_host_pause())
	settings_screen.scale_changed.connect(apply_ui_scale)
	settings_screen.closed.connect(
		func() -> void: ctx.matcher.invert_pitch = ctx.settings.invert_pitch
	)
	settings_screen.reference_plane_requested.connect(
		func() -> void: ctx.settings.reference_plane = ctx.interp.own_rotation()
	)
