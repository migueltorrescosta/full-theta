class_name TrainingPicker
extends PanelContainer
## The Training picker (D303, FT-MIS-039, FT-STN-005): the Crew drill first, for a group (the
## Shakedown with a crew: this player hosts, friends join, ux-05), then the solo lessons: one
## card per station lesson, Helm marked as the one to start with (R26-12), and the Callouts
## quiz (CalloutsQuiz, ux-11). A tick marks those done on this device
## (ClientSettings.lessons_done). A tap on a card emits `chosen` with the station id, "" for
## the crew drill or CALLOUTS for the quiz; the menu starts it. Any lesson is two taps from the
## main menu and can be played again any time. On the web a server with crew answers `busy`,
## which the menu shows here with show_busy().

signal chosen(station: String)
signal closed

## The lessons, in the order of the cards (the first six are the crew stations, then Captain).
const LESSONS: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "captain"
]
## The Callouts quiz's id among the cards and in ClientSettings.lessons_done.
const CALLOUTS: String = "callouts"
## The lesson a new player should take first (R26-12).
const FIRST: String = "helm"
const CARD_W: float = 160.0
const CARD_H: float = 120.0

var settings: ClientSettings
## Steps of each station's whole track, shown on its card ("46 steps").
var steps: Dictionary[String, int] = {}

var _grid: GridContainer
var _scroll: ScrollContainer
var _title: Label
var _count: Label
var _note: Label
var _drill: Button
var _callouts: Button
var _cards: Dictionary[String, Button] = {}
var _box: StyleBoxFlat
var _back: Button


func setup(p_settings: ClientSettings, step_list: TrainingStepsDef) -> void:
	settings = p_settings
	for station: String in LESSONS:
		steps[station] = step_list.track(StringName(station)).size() if step_list != null else 0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = UiTheme.box("panel", "line_strong", 16, 16)
	add_theme_stylebox_override("panel", _box)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(root)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	root.add_child(head)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "‹ " + tr("settings.close")
	_back.custom_minimum_size = Vector2(0, UiTheme.TOUCH_PRIMARY)
	_back.pressed.connect(func() -> void: closed.emit())
	head.add_child(_back)
	_title = Label.new()
	_title.name = "Title"
	_title.text = tr("train.picker.title")
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = Label.new()
	_count.name = "Count"
	_count.add_theme_color_override("font_color", Palette.color("text_dim"))
	head.add_child(_count)
	_note = Label.new()
	_note.name = "Note"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	root.add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_scroll.add_child(body)
	body.add_child(_heading("GroupHeading", "train.picker.group"))
	# The crew drill, one line the width of the grid.
	_drill = _drill_card()
	body.add_child(_drill)
	body.add_child(_heading("SoloHeading", "train.picker.solo"))
	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	body.add_child(_grid)
	for station: String in LESSONS:
		var card_button: Button = _card(station)
		_cards[station] = card_button
		_grid.add_child(card_button)
	# The Callouts quiz is the eighth card, so the grid is two rows of four on a wide window.
	_callouts = _card(CALLOUTS)
	_grid.add_child(_callouts)
	refresh()
	fit()


## The text, ticks and columns for the current settings and window.
func refresh() -> void:
	_title.text = tr("train.picker.title")
	_back.text = "‹ " + tr("settings.close")
	(find_child("GroupHeading", true, false) as Label).text = tr("train.picker.group")
	(find_child("SoloHeading", true, false) as Label).text = tr("train.picker.solo")
	var done: int = 0
	for station: String in LESSONS + [CALLOUTS]:
		var is_done: bool = settings.lesson_done(station)
		done += 1 if is_done else 0
		_fill(_callouts if station == CALLOUTS else _cards[station], station, is_done)
	_count.text = tr("train.picker.done_count") % [done, LESSONS.size() + 1]
	(_drill.find_child("Name", true, false) as Label).text = tr("train.picker.drill")
	(_drill.find_child("Dot", true, false) as Label).text = tr("train.picker.drill").left(1)
	(_drill.find_child("Blurb", true, false) as Label).text = (
		"%s · %s" % [tr("train.picker.drill_hint"), tr("train.picker.drill_size")]
	)
	(_drill.find_child("State", true, false) as Label).text = tr("train.picker.start")


## Keeps the picker inside the safe area and picks its columns: two on a phone held upright,
## four otherwise.
func fit() -> void:
	if _box == null or not is_inside_tree():
		return
	var m: Vector4 = SafeArea.margins(self)
	_box.content_margin_left = 16.0 + m.x
	_box.content_margin_top = 16.0 + m.y
	_box.content_margin_right = 16.0 + m.z
	_box.content_margin_bottom = 16.0 + maxf(m.w, SafeArea.tap_band(self))
	var upright: bool = LayoutMode.form_of(self) == LayoutMode.Form.PHONE_PORTRAIT
	_grid.columns = 2 if upright else 4
	var phone: bool = LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	# One line on a wide window; upright, its words wrap to a second line.
	_drill.custom_minimum_size = Vector2(0, 76 if upright else UiTheme.TOUCH_PRIMARY + 4)
	(_drill.find_child("Name", true, false) as Label).theme_type_variation = (
		&"" if phone else &"HeadingLabel"
	)
	for card: Button in _cards.values() + [_callouts]:
		card.custom_minimum_size = Vector2(0 if upright else CARD_W, CARD_H)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Names and blurbs are 16 px on a phone, where two cards share the width.
		for label: Label in [_name_of(card), _blurb_of(card)]:
			label.theme_type_variation = &"" if phone else &"HeadingLabel"


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		fit()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and settings != null and _grid != null:
		refresh()


## Says why a lesson did not start ("" clears it), and opens the cards again.
func show_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""
	set_busy(false)


## "The server is busy: N players are on it" after a refused request on the web.
func show_busy(players: int) -> void:
	show_note(tr("train.picker.busy_one" if players == 1 else "train.picker.busy_many") % players)


## While a lesson is starting the cards ignore taps.
func set_busy(on: bool) -> void:
	for card_button: Button in _cards.values() + [_callouts, _drill]:
		card_button.disabled = on


## The card of a station's lesson, or of CALLOUTS; null for another id.
func card(station: String) -> Button:
	return _callouts if station == CALLOUTS else _cards.get(station)


## The Crew drill card (it emits `chosen` with "").
func crew_drill() -> Button:
	return _drill


## A section heading over the cards.
func _heading(node_name: String, key: String) -> Label:
	var l: Label = Label.new()
	l.name = node_name
	l.text = tr(key)
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _name_of(card_button: Button) -> Label:
	return card_button.get_node("Pad").get_child(0).get_node("Head/Name") as Label


func _blurb_of(card_button: Button) -> Label:
	return card_button.get_node("Pad").get_child(0).get_node("Blurb") as Label


## The crew drill's card: one line of its name, what it is and Start; it emits "".
func _drill_card() -> Button:
	var b: Button = Button.new()
	b.name = "CrewDrill"
	b.pressed.connect(func() -> void: chosen.emit(""))
	var pad: MarginContainer = MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	b.add_child(pad)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	pad.add_child(row)
	var dot: Label = _dot("drill")
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var title: Label = _label("Name", row, false)
	title.clip_text = false
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var blurb: Label = _label("Blurb", row, true)
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	blurb.add_theme_color_override("font_color", Palette.color("text_dim"))
	var state: Label = _label("State", row, true)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state.add_theme_color_override("font_color", Palette.color("accent"))
	return b


## A card: `station` a station id or CALLOUTS.
func _card(station: String) -> Button:
	var b: Button = Button.new()
	b.name = station.capitalize()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = false
	b.pressed.connect(func() -> void: chosen.emit(station))
	var pad: MarginContainer = MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	b.add_child(pad)
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	pad.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	head.add_child(_dot(station))
	var name_label: Label = _label("Name", head, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tick: Label = _label("Tick", head, true)
	tick.custom_minimum_size = Vector2(14, 0)
	tick.add_theme_color_override("font_color", Palette.color("ok"))
	_label("Blurb", col, false)
	_label("Size", col, true).add_theme_color_override("font_color", Palette.color("text_dim"))
	_label("State", col, true)
	return b


func _label(node_name: String, parent: Control, small: bool) -> Label:
	var l: Label = Label.new()
	l.name = node_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the blurb wraps; a name or tick that wrapped would stretch its row.
	if node_name == "Blurb":
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif node_name == "Name":
		l.clip_text = true
	if small:
		l.add_theme_font_size_override("font_size", UiTheme.SMALL_SIZE + 1)
	parent.add_child(l)
	return l


## The card's coloured letter disc (a station's tint says the station only with the name
## beside it); the crew drill and the quiz wear the accent.
func _dot(station: String) -> Label:
	var d: Label = Label.new()
	d.name = "Dot"
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(26, 26)
	d.add_theme_color_override("font_color", Palette.color("background"))
	var tint: String = "st_" + station if station in LESSONS else "accent"
	var s: StyleBoxFlat = UiTheme.box(tint, "", 0, 0)
	s.set_corner_radius_all(13)
	d.add_theme_stylebox_override("normal", s)
	return d


## The card's name, blurb and size line keys.
static func _words(station: String) -> PackedStringArray:
	if station == CALLOUTS:
		return ["train.picker.callouts", "train.blurb.callouts", "train.picker.questions"]
	return [StationCatalogue.name_key(station), "train.blurb." + station, "train.picker.steps"]


func _fill(card_button: Button, station: String, done: bool) -> void:
	var col: Control = card_button.get_node("Pad").get_child(0)
	var words: PackedStringArray = _words(station)
	var title: String = tr(words[0])
	(col.get_node("Head/Dot") as Label).text = title.left(1)
	(col.get_node("Head/Name") as Label).text = title
	(col.get_node("Head/Tick") as Label).text = "✓" if done else ""
	(col.get_node("Blurb") as Label).text = tr(words[1])
	var size_text: String = tr(words[2])
	if "%d" in size_text:
		var n: int = CalloutsQuiz.QUESTIONS if station == CALLOUTS else steps.get(station, 0)
		size_text = size_text % n
	(col.get_node("Size") as Label).text = size_text
	var state: Label = col.get_node("State")
	state.text = tr("train.picker.again") if done else tr("train.picker.start")
	if station == FIRST and not done:
		state.text = tr("train.picker.start_here")
	state.add_theme_color_override("font_color", Palette.color("ok" if done else "accent"))
