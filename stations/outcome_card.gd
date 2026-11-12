class_name OutcomeCard
extends PanelContainer
## The end-of-run card (FT-M1-012, D178, ux-20): on every station of a ship whose run ended,
## one card: the result (Victory or Ship lost, why, the run time and hull left), the encounters
## that ended partial (limped home, out of time; gp-09), up to three
## highlights (the best pair moment, the closest call, the top kill; RunHighlights' fixed
## rules, a highlight with no data left out), and Run again. Crew cast or withdraw a "Run
## again" vote (voters and votes needed shown, like the give-up vote); the host runs it again
## at once. Details swaps the summary for the full debrief (DebriefCard) and Back swaps it
## back. The card goes when the server resets the run (CrewState.reset_run).
##
## Phones (#28 follow-up, design 2.13): the card fills the safe area above the gesture band,
## opaque; the debrief scrolls, and the buttons sit at the bottom right (thumb side). There are
## no tabs: Details is the same button everywhere. Tablets and desktops keep the centred card.

## The crew changes the card depends on.
const KINDS: Array[StringName] = [&"ship_outcome", &"reset", &"picked", &"catalogue", &"debrief"]
## The least width of Run again and Vote on a phone, px.
const PHONE_BUTTON_W: float = 160.0

var ctx: StationContext

var _col: VBoxContainer
var _info: VBoxContainer
var _spacer: Control
var _title: Label
var _why: Label
var _stats: Label
var _partial: Label
var _highlights: VBoxContainer
var _votes: Label
var _note: Label
var _buttons: HBoxContainer
var _debrief: DebriefCard
var _phone: bool = false
## Details is open: the full debrief shows in place of the summary.
var _details: bool = false
## The host tapped Run again once with players still deciding: the next tap runs it anyway,
## as long as the same players are still deciding (C14).
var _force: bool = false
var _force_for: PackedStringArray = PackedStringArray()


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
	_why = Label.new()
	_why.name = "Why"
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(_why)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_stats)
	_partial = Label.new()
	_partial.name = "Partial"
	_partial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_partial.add_theme_color_override("font_color", Palette.color("warn"))
	_info.add_child(_partial)
	_highlights = VBoxContainer.new()
	_highlights.name = "Highlights"
	_highlights.add_theme_constant_override("separation", 2)
	_info.add_child(_highlights)
	_votes = Label.new()
	_votes.name = "Votes"
	_votes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(_votes)
	_note = Label.new()
	_note.name = "Note"
	_note.theme_type_variation = "DimLabel"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(_note)
	# (the debrief, in place of the summary while Details is open)
	_debrief = DebriefCard.new()
	_debrief.name = "Debrief"
	_debrief.visible = false
	_col.add_child(_debrief)
	_debrief.setup(ctx)
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
	ctx.crew.changed.connect(_on_crew_changed)
	resized.connect(_place)
	# (a label that starts to wrap shrinks the content after the size was set)
	minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	refresh()


func _enter_tree() -> void:
	PhoneSheet.follow_viewport(self, _place)
	_place.call_deferred()


func refresh() -> void:
	var card: Dictionary = ctx.crew.ship_outcome.get(ctx.crew.ship, {})
	visible = not card.is_empty() and ctx.crew.seat != ""
	if not visible:
		return
	_place()
	_title.text = tr("outcome.win" if card.get("outcome", "") == "win" else "outcome.loss")
	_why.text = why_text(card)
	var secs: int = int(card.get("time", 0.0))
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
	_fill_highlights(ctx.crew.debrief.get(ship, {}).get("highlights", {}))
	_partial.text = partial_line(ctx.crew.debrief.get(ship, {}))
	_partial.visible = _partial.text != ""
	if not _debrief.available():
		_details = false
	else:
		var label: String = "‹ " + tr("settings.close") if _details else tr("outcome.details")
		_button("Details", label).pressed.connect(show_details.bind(not _details))
	_info.visible = not _details
	_debrief.visible = _details
	_spacer.visible = _phone and not _details
	_note.text = ""
	if ctx.crew.host:
		var waiting: PackedStringArray = waiting_names(card)
		if waiting != _force_for:
			_force = false
		var run: Button = _button("RunAgain", tr("outcome.restart"))
		if _force:
			run.text = tr("outcome.force") % ", ".join(waiting)
		run.pressed.connect(_host_run_again.bind(run))
	elif ctx.crew.is_crew():
		var voted: bool = ctx.crew.session in card.get("sessions", [])
		_button("Vote", tr("outcome.unvote") if voted else tr("outcome.vote")).pressed.connect(
			func() -> void: ctx.intents.run_again(ship, not voted)
		)
	else:
		_note.text = tr("outcome.watch")


## Details on: the full debrief in place of the summary; off: the summary again.
func show_details(on: bool) -> void:
	_details = on and _debrief.available()
	refresh()


## Whether Details is open.
func details_open() -> bool:
	return _details


## The highlight lines of a debrief's `highlights` record, in the card's order (best pair,
## closest call, top kill), each only when present.
static func highlight_lines(h: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if h.has("best_pair"):
		var pair: Dictionary = h["best_pair"]
		var names: PackedStringArray = PackedStringArray()
		for station: String in pair.get("stations", []):
			names.append(_t("debrief.station.%s" % station))
		var n: int = int(pair.get("events", 0))
		var key: String = "outcome.hl_pair_one" if n == 1 else "outcome.hl_pair"
		out.append(_t(key).format({"pair": " + ".join(names), "n": n}))
	if h.has("closest_call"):
		var c: Dictionary = h["closest_call"]
		var hull: int = maxi(1, roundi(float(c.get("hull", 0.0)) * 100.0))
		var at: String = DebriefCard.clock(float(c.get("time", 0.0)))
		out.append(_t("outcome.hl_close").format({"hull": hull, "time": at}))
	if h.has("top_kill"):
		var k: Dictionary = h["top_kill"]
		var at: String = DebriefCard.clock(float(k.get("time", 0.0)))
		out.append(_t("outcome.hl_kill").format({"name": str(k.get("name", "")), "time": at}))
	return out


## The encounters that ended partial, on half pay (gp-09, D419: the one card shows them): how
## many limped home and how many ran out of time, each only when there is one; "" for none.
static func partial_line(debrief: Dictionary) -> String:
	var limped: int = 0
	var late: int = 0
	for row: Dictionary in debrief.get("encounters", []):
		if row.get("lost", false) or row.get("fled", false):
			continue
		if row.get("limped", false):
			limped += 1
		elif str(row.get("result", "")) == "partial":
			late += 1
	var parts: PackedStringArray = PackedStringArray()
	if limped > 0:
		parts.append(_t("outcome.limped") % limped)
	if late > 0:
		parts.append(_t("outcome.out_of_time") % late)
	return " · ".join(parts)


## Why the run ended, in one line: the win rule, or how the ship was lost.
static func why_text(card: Dictionary) -> String:
	if card.get("outcome", "") == "win":
		return TranslationServer.translate("outcome.why_win")
	if float(card.get("hull", 0.0)) <= 0.0:
		return TranslationServer.translate("outcome.why_destroyed")
	return TranslationServer.translate("outcome.why_gave_up")


func _fill_highlights(h: Dictionary) -> void:
	var lines: PackedStringArray = highlight_lines(h)
	for c: Node in _highlights.get_children():
		_highlights.remove_child(c)
		c.queue_free()
	for line: String in lines:
		var l: Label = Label.new()
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Palette.color("accent"))
		# A phone's card has the screen's width, so a long line wraps there; off a phone the
		# lines set the centred card's width (a wrapping label has no least width).
		if _phone:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_highlights.add_child(l)
	_highlights.visible = not lines.is_empty()


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


## The crew who haven't voted to run again yet, apart from the host: the ship's crew seats
## (the `lobby` payload) minus this card's voters.
func waiting_names(card: Dictionary) -> PackedStringArray:
	var voters: Array = card.get("voters", [])
	var out: PackedStringArray = PackedStringArray()
	for seat: Dictionary in ctx.crew.ship_state(ctx.crew.ship).get("seats", []):
		var who: String = str(seat.get("name", ""))
		if StationCatalogue.is_crew(str(seat.get("seat", ""))) and who != ctx.settings.player_name:
			if not voters.has(who) and not out.has(who):
				out.append(who)
	return out


## The host's Run again: at once when every crew player voted (the vote would pass anyway) or
## nobody is left to wait for; else the first tap names who is still deciding and the second
## runs it anyway.
func _host_run_again(button: Button) -> void:
	var card: Dictionary = ctx.crew.ship_outcome.get(ctx.crew.ship, {})
	var waiting: PackedStringArray = waiting_names(card)
	if waiting.is_empty() or _force:
		_force = false
		ctx.intents.run_again(ctx.crew.ship, true)
		return
	_force = true
	_force_for = waiting
	button.text = tr("outcome.force") % ", ".join(waiting)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	if _phone:
		# The row spans the card's content, from edge to edge, on a phone.
		b.custom_minimum_size = Vector2(PHONE_BUTTON_W, UiTheme.TOUCH_PRIMARY)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.add_child(b)
	return b


## On a phone the card fills the safe area above the gesture band; elsewhere
## it is the shell's centred card.
func _place() -> void:
	if not is_inside_tree() or ctx == null:
		return
	var phone: bool = PhoneSheet.is_phone(self)
	if phone != _phone:
		_set_phone(phone)
	if not phone:
		return
	PhoneSheet.fit(self)


## Switches between the phone's full-screen card and the centred card.
func _set_phone(phone: bool) -> void:
	_phone = phone
	_debrief.set_compact(phone)
	# (no autowrap: a wrapped label's height at zero width would grow the card)
	_votes.clip_text = phone
	# (a phone on its side has room for the summary with its highlights only this tight)
	_info.add_theme_constant_override("separation", 4 if phone else 10)
	_votes.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_buttons.alignment = BoxContainer.ALIGNMENT_END if phone else BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", UiTheme.TOUCH_GAP if phone else 4)
	if not phone:
		PhoneSheet.unfit(self)
	refresh()


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
