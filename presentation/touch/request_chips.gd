class_name RequestChips
extends VBoxContainer
## Incoming request chips on a phone's view-top row (#28 follow-up, P28-Common, design 1.3,
## FT-PAIR-013): one row per chip another station sent here, "Helm: Boost · 18 s", with ✓
## (accept) and ✕ (decline), and under it what accepting does (`effect`, C5). A chip nobody
## answers leaves a "lapsed" note for a few seconds (ChipLapse); notices (a partner's shared
## data still live) are rows without buttons. The rows rebuild only when the set changes; the
## seconds update in place.
##
##     chips.answered.connect(func(id: int, yes: bool) -> void: ctx.intents.answer_chip(id, yes))
##     chips.show_chips([{"id": 4, "text": "Helm: Boost", "left": 18.0, "effect": "..."}])

## ✓ or ✕ on chip `id`.
signal answered(id: int, accept: bool)

const TEXT_W: float = 150.0
const FONT: int = 13

var _keys: Array = []
var _ids: Array[int] = []
var _labels: Array[Label] = []
var _lapse: ChipLapse = ChipLapse.new()


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## `chips`: [{id, text, left (seconds), effect (optional)}], oldest first; `notices`: one
## button-less row each, after the chips and the lapsed notes. `now_ms` is the clock the
## lapsed notes run on (the wall clock by default).
func show_chips(chips: Array, notices: Array[String] = [], now_ms: int = -1) -> void:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var notes: Array[String] = _lapse.update(chips, now)
	notes.append_array(notices)
	var keys: Array = []
	var ids: Array[int] = []
	for c: Dictionary in chips:
		keys.append([int(c["id"]), str(c.get("effect", ""))])
		ids.append(int(c["id"]))
	for n: String in notes:
		keys.append(n)
	if keys != _keys:
		_keys = keys
		_ids = ids
		_rebuild(chips, notes)
	for i: int in chips.size():
		var text: String = "%s · %d s" % [chips[i]["text"], ceili(float(chips[i]["left"]))]
		if _labels[i].text != text:
			_labels[i].text = text
	visible = not keys.is_empty()


## The ✓ and ✕ buttons of row `i` (tests).
func buttons(i: int) -> Array[RailButton]:
	var out: Array[RailButton] = []
	if i < 0 or i >= get_child_count():
		return out
	for c: Node in get_child(i).get_child(0).get_children():
		if c is RailButton:
			out.append(c)
	return out


func _rebuild(chips: Array, notes: Array[String]) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_labels.clear()
	for i: int in chips.size():
		var id: int = _ids[i]
		var row: PanelContainer = _row("accent")
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		row.add_child(line)
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var l: Label = _label(true)
		text.add_child(l)
		_labels.append(l)
		var effect: String = str(chips[i].get("effect", ""))
		if effect != "":
			var e: Label = _label(false)
			e.text = effect
			e.add_theme_color_override("font_color", Palette.color("text_dim"))
			text.add_child(e)
		var yes: RailButton = RailButton.make("✓", RailButton.Role.ACCENT)
		yes.name = "Accept"
		yes.pressed.connect(func() -> void: answered.emit(id, true))
		var no: RailButton = RailButton.make("✕")
		no.name = "Decline"
		no.pressed.connect(func() -> void: answered.emit(id, false))
		line.add_child(yes)
		line.add_child(no)
		add_child(row)
	for n: String in notes:
		var row: PanelContainer = _row("line_strong")
		var l: Label = _label(false)
		l.text = n
		row.add_child(l)
		add_child(row)


func _row(border: String) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA)
	sb.border_color = Palette.color(border)
	sb.set_border_width_all(UiTheme.BORDER)
	sb.set_corner_radius_all(UiTheme.RADIUS)
	sb.content_margin_left = UiTheme.TOUCH_GAP
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _label(tall: bool) -> Label:
	var l: Label = Label.new()
	l.custom_minimum_size.x = TEXT_W
	l.add_theme_font_size_override("font_size", FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tall:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
