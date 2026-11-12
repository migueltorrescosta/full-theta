class_name PauseOverlay
extends PanelContainer
## The pause (FT-NET-034, D96, D128): shown while a ship in play is paused, naming the
## uncovered stations. Crew of the paused ship get one "Give up (2/3)" toggle: their abandon
## vote, cast or withdrawn, with the votes so far and the votes needed (#37 C11). The host
## also gets "End now", which asks "End the game?" and then ends the game for everyone, as
## the lobby's End game does (D353; `end_requested`, ClientShell.leave). The Captain and
## viewers of that ship may take over an uncovered station (FT-NET-042).
##
## Multi-ship games (#11, M4-Q8, D265 proposed): players of an allied ship may take over a
## paused ship's uncovered station too ("Take Science on Heron"); there is no accept prompt,
## the first claim wins, and the server refuses a takeover that would leave the taker's own
## ship uncovered. A hostile ship's pause offers nothing. In PvP the vote is the give-up
## (forfeit) vote (M4-Q10).
##
## On a phone (#28 follow-up, design 2.13) the overlay is an opaque sheet over the safe area
## between the station's top bar and its bottom tabs (or the gesture band), its text at the
## top and its buttons at the bottom right (thumb side); tablets and desktops keep the
## shell's centred card.

## The host confirmed End now: the shell ends the game for everyone (D353).
signal end_requested

## The crew changes the overlay depends on.
const KINDS: Array[StringName] = [&"pause", &"votes", &"picked", &"catalogue", &"fleet"]

var ctx: StationContext

var _text: Label
## What the crew of the paused ship can do, under the heading.
var _hint: Label
var _buttons: HFlowContainer
var _end_dialog: ConfirmationDialog
var _spacer: Control
var _phone: bool = false


func setup(context: StationContext) -> void:
	ctx = context
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_text = Label.new()
	_text.theme_type_variation = "HeadingLabel"
	col.add_child(_text)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = "DimLabel"
	col.add_child(_hint)
	_spacer = Control.new()
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.visible = false
	col.add_child(_spacer)
	_buttons = HFlowContainer.new()
	_buttons.name = "Buttons"
	_buttons.add_theme_constant_override("h_separation", 8)
	_buttons.add_theme_constant_override("v_separation", 8)
	col.add_child(_buttons)
	_end_dialog = ConfirmationDialog.new()
	_end_dialog.name = "EndDialog"
	_end_dialog.confirmed.connect(end_requested.emit)
	add_child(_end_dialog)
	ctx.crew.changed.connect(_on_crew_changed)
	resized.connect(_place)
	# (a label that starts to wrap shrinks the content after the size was set)
	minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	refresh()


func _enter_tree() -> void:
	PhoneSheet.follow_viewport(self, _place)
	_place.call_deferred()


## On a phone the sheet fills the main area above the band; elsewhere the shell's card.
func _place() -> void:
	if not is_inside_tree() or ctx == null:
		return
	var phone: bool = PhoneSheet.is_phone(self)
	if phone != _phone:
		_set_phone(phone)
	if not phone:
		return
	# Under the top bar, which stays live (☰ for Leave, the status and timer), and above the
	# station's bottom tabs (upright), which it must not cover (D319).
	PhoneSheet.fit(self, VotePrompt.main_top(self), _tabs_top())


## The top of the station's bottom tab bar (viewport px) while it shows, else INF.
func _tabs_top() -> float:
	var parent: Node = get_parent()
	if parent != null:
		for n: Node in parent.find_children("*", "StationScreen", true, false):
			var s: StationScreen = n
			if (
				s.is_visible_in_tree()
				and s.frame != null
				and s.frame.bottom_tabs.is_visible_in_tree()
			):
				return s.frame.bottom_tabs.get_global_rect().position.y - UiTheme.TOUCH_GAP
	return INF


func _set_phone(phone: bool) -> void:
	_phone = phone
	_spacer.visible = phone
	_buttons.alignment = FlowContainer.ALIGNMENT_END if phone else FlowContainer.ALIGNMENT_BEGIN
	for l: Label in [_text, _hint]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if phone else TextServer.AUTOWRAP_OFF
	if phone:
		var sheet: StyleBoxFlat = UiTheme.box("panel", "line_strong", 16, 16)
		# Opaque: it blocks the station under it, which a ghost of the HUD would only
		# confuse (D319).
		add_theme_stylebox_override("panel", sheet)
	else:
		remove_theme_stylebox_override("panel")
		PhoneSheet.unfit(self)


## The paused ship this client cares about: its own, else an allied one, else any.
func paused_ship() -> int:
	if ctx.crew.paused.has(ctx.crew.ship):
		return ctx.crew.ship
	for id: Variant in ctx.crew.paused:
		if ctx.crew.allied(int(id), ctx.crew.ship):
			return int(id)
	return int(ctx.crew.paused.keys()[0]) if not ctx.crew.paused.is_empty() else -1


## Whether this client may offer to take over a station on the paused `id` (M4-Q8): its own
## ship's Captain and viewers, or any player of an allied ship; never an enemy.
func may_take_over(id: int) -> bool:
	if id == ctx.crew.ship:
		return not ctx.crew.is_crew()
	return ctx.crew.seat != "" and ctx.crew.allied(id, ctx.crew.ship)


func refresh() -> void:
	var id: int = paused_ship()
	visible = id >= 0 or ctx.crew.host_paused
	if not visible:
		return
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	_hint.visible = false
	if id < 0:
		# A host pause alone (FT-MIS-040): no uncovered list, no vote.
		_text.text = tr("pause.host")
		_resume_button()
		_end_button()
		return
	var p: Dictionary = ctx.crew.paused[id]
	var names: PackedStringArray = []
	for s: Variant in p.get("uncovered", []):
		names.append(tr(StationCatalogue.name_key(str(s))))
	var own: bool = id == ctx.crew.ship
	if own:
		_text.text = tr("pause.waiting") % ", ".join(names)
	else:
		_text.text = tr("pause.waiting_ship") % [ctx.crew.ship_name(id), ", ".join(names)]
	if own and ctx.crew.is_crew():
		_hint.text = tr("pause.hint")
		_hint.visible = true
		_vote_button(id)
	elif may_take_over(id):
		for s: Variant in p.get("uncovered", []):
			var st: String = str(s)
			var text: String = tr("pause.take") % tr(StationCatalogue.name_key(st))
			if not own:
				text = (
					tr("pause.take_on")
					% [tr(StationCatalogue.name_key(st)), ctx.crew.ship_name(id)]
				)
			_button("Takeover_" + st, text).pressed.connect(
				func() -> void: ctx.intents.takeover(id, st)
			)
	_resume_button()
	_end_button()


## The crew's one give-up toggle (#37 C11, D128; the forfeit in PvP, M4-Q10): "Give up (2/3)",
## the votes so far and the votes needed, pressed while this player's vote stands.
func _vote_button(id: int) -> void:
	var v: Dictionary = ctx.crew.votes.get(id, {"voters": [], "needed": 0})
	var voted: bool = ctx.crew.session in v.get("sessions", [])
	var count: Array = [v.get("voters", []).size(), int(v.get("needed", 0))]
	var b: Button = _button("Vote", tr("pause.give_up_on" if voted else "pause.give_up") % count)
	b.toggle_mode = true
	b.set_pressed_no_signal(voted)
	b.pressed.connect(func() -> void: ctx.intents.vote_abandon(id, not voted))


## End now, on the host's client only (#37 C11): "End the game?", then the game ends for
## everyone (D353).
func _end_button() -> void:
	if ctx.crew.host:
		_button("EndNow", tr("pause.end_now")).pressed.connect(open_end_dialog)


## Asks the host "End the game?" (the lobby's End game dialog, D353).
func open_end_dialog() -> void:
	_end_dialog.title = tr("lobby.end_title")
	_end_dialog.dialog_text = tr("lobby.end_text")
	_end_dialog.ok_button_text = tr("lobby.end_game")
	_end_dialog.cancel_button_text = tr("lobby.end_keep")
	_end_dialog.popup_centered()


## Resume, on the host's client during a host pause (also over a coverage pause).
func _resume_button() -> void:
	if ctx.crew.host_paused and ctx.crew.host:
		_button("Resume", tr("pause.resume")).pressed.connect(
			func() -> void: ctx.intents.host_pause(false)
		)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, UiTheme.TOUCH_PRIMARY)
	_buttons.add_child(b)
	return b


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
