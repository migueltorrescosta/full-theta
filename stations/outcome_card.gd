class_name OutcomeCard
extends PanelContainer
## The outcome card (FT-M1-012, D178): on every station of a ship whose run ended, Victory
## or Ship lost with the run time and hull left. Crew cast or withdraw a "Run again" vote
## (voters and votes needed shown, like the abandon vote); the host runs it again at
## once. The card goes when the server resets the run (CrewState.reset_run).
##
## Phones (#28 follow-up, design 2.13): the card fills the safe area above the gesture
## band, opaque, with Outcome and Debrief as two tabs at its top (`pages`, `tabs`) instead
## of the Open debrief button; the debrief scrolls, and Run again or Vote sits at the
## bottom right (thumb side). Tablets and desktops keep the centred card.

## The crew changes the card depends on.
const KINDS: Array[StringName] = [&"run_over", &"reset", &"picked", &"catalogue", &"debrief"]
## The least width of Run again and Vote on a phone, px.
const PHONE_BUTTON_W: float = 160.0

var ctx: StationContext
## The phone's two pages (Outcome, Debrief); null off a phone.
var pages: PageHost
## The phone's tabs; null off a phone.
var tabs: PageTabs

var _col: VBoxContainer
var _info: VBoxContainer
var _spacer: Control
var _title: Label
var _stats: Label
var _votes: Label
var _buttons: HBoxContainer
var _debrief: DebriefCard
var _phone: bool = false


func setup(context: StationContext) -> void:
	ctx = context
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	add_child(_col)
	_info = VBoxContainer.new()
	_info.name = "Outcome"
	_info.add_theme_constant_override("separation", 10)
	_col.add_child(_info)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = "TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_title)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_stats)
	_votes = Label.new()
	_votes.name = "Votes"
	_info.add_child(_votes)
	_spacer = Control.new()
	_spacer.name = "Spacer"
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.visible = false
	_col.add_child(_spacer)
	_buttons = HBoxContainer.new()
	_buttons.name = "Buttons"
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_child(_buttons)
	# (the debrief, opened by its button, or its tab on a phone)
	_debrief = DebriefCard.new()
	_debrief.name = "Debrief"
	_debrief.visible = false
	_col.add_child(_debrief)
	_debrief.setup(ctx)
	ctx.crew.changed.connect(_on_crew_changed)
	resized.connect(_place)
	# (a label that starts to wrap shrinks the content after the size was set)
	minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	refresh()


func _enter_tree() -> void:
	if not get_viewport().size_changed.is_connected(_place):
		get_viewport().size_changed.connect(_place)
	_place.call_deferred()


func refresh() -> void:
	var card: Dictionary = ctx.crew.run_over.get(ctx.crew.ship, {})
	visible = not card.is_empty() and ctx.crew.entry != ""
	if not visible:
		return
	_place()
	_title.text = tr("outcome.win" if card.get("outcome", "") == "win" else "outcome.loss")
	var secs: int = int(card.get("time_s", 0.0))
	var hull: int = roundi(float(card.get("hull", 0.0)) * 100.0)
	_stats.text = tr("outcome.stats") % ["%d:%02d" % [secs / 60, secs % 60], hull]
	var voters: Array = card.get("voters", [])
	_votes.text = (
		tr("outcome.votes") % [voters.size(), int(card.get("needed", 0)), ", ".join(voters)]
	)
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var ship: int = ctx.crew.ship
	if _phone:
		tabs.visible = _debrief.available()
		if not _debrief.available():
			pages.select(0)
	elif _debrief.available():
		_button("OpenDebrief", tr("debrief.open")).pressed.connect(
			func() -> void: _debrief.visible = not _debrief.visible
		)
	else:
		_debrief.visible = false
	if ctx.crew.host:
		_button("RunAgain", tr("outcome.restart")).pressed.connect(
			func() -> void: ctx.intents.run_again(ship, true)
		)
	elif ctx.crew.is_crew():
		var voted: bool = ctx.crew.session in card.get("sessions", [])
		_button("Vote", tr("outcome.unvote") if voted else tr("outcome.vote")).pressed.connect(
			func() -> void: ctx.intents.run_again(ship, not voted)
		)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	if _phone:
		b.custom_minimum_size = Vector2(PHONE_BUTTON_W, UiTheme.TOUCH_PRIMARY)
	_buttons.add_child(b)
	return b


## On a phone the card fills the safe area above the gesture band, with its tabs; elsewhere
## it is the shell's centred card.
func _place() -> void:
	if not is_inside_tree() or ctx == null:
		return
	var phone: bool = LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	if phone != _phone:
		_set_phone(phone)
	if not phone:
		return
	var r: Rect2 = SafeArea.tap_rect(self)
	var parent: Control = get_parent() as Control
	if parent != null:
		r = SafeArea.to_local(parent, r)
	if position != r.position or size != r.size:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		custom_minimum_size = r.size
		position = r.position
		size = r.size


## Switches between the phone's full-screen card with tabs and the centred card.
func _set_phone(phone: bool) -> void:
	_phone = phone
	_debrief.set_compact(phone)
	_spacer.visible = phone
	# (no autowrap: a wrapped label's height at zero width would grow the card)
	_votes.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if phone else HORIZONTAL_ALIGNMENT_LEFT
	)
	_votes.clip_text = phone
	_votes.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_buttons.alignment = BoxContainer.ALIGNMENT_END if phone else BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", UiTheme.TOUCH_GAP if phone else 4)
	if phone:
		pages = PageHost.new()
		pages.add_page(TouchText.of("outcome.tab", "Outcome"), [_info, _spacer])
		pages.add_page(TouchText.of("debrief.tab", "Debrief"), [_debrief])
		tabs = PageTabs.new()
		tabs.name = "Tabs"
		tabs.upright = true
		_col.add_child(tabs)
		_col.move_child(tabs, 0)
		tabs.bind(pages)
		_col.move_child(_debrief, _spacer.get_index())
		_col.move_child(_buttons, -1)
	else:
		if tabs != null:
			tabs.queue_free()
		tabs = null
		pages = null
		_info.visible = true
		_spacer.visible = false
		_debrief.visible = false
		_col.move_child(_debrief, -1)
		custom_minimum_size = Vector2.ZERO
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BOTH
	refresh()


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
