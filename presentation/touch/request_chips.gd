class_name RequestChips
extends VBoxContainer
## Incoming request chips on a phone's view-top row (#28 follow-up, P28-Common, design 1.3,
## FT-PAIR-013): one row per chip another station sent here, "Helm: Boost · 18 s", with ✓
## (accept) and ✕ (decline). A chip nobody answers simply goes when its time is up. The
## rows rebuild only when the set of chips changes; the seconds update in place.
##
##     chips.answered.connect(func(id: int, yes: bool) -> void: ctx.intents.answer_chip(id, yes))
##     chips.show_chips([{"id": 4, "text": "Helm: Boost", "left": 18.0}])

## ✓ or ✕ on chip `id`.
signal answered(id: int, accept: bool)

const TEXT_W: float = 150.0
const FONT: int = 13

var _ids: Array[int] = []
var _labels: Array[Label] = []


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## `chips`: [{id, text, left (seconds)}], oldest first.
func show_chips(chips: Array) -> void:
	var ids: Array[int] = []
	for c: Dictionary in chips:
		ids.append(int(c["id"]))
	if ids != _ids:
		_ids = ids
		_rebuild(chips.size())
	for i: int in chips.size():
		var text: String = "%s · %d s" % [chips[i]["text"], ceili(float(chips[i]["left"]))]
		if _labels[i].text != text:
			_labels[i].text = text
	visible = not chips.is_empty()


## The ✓ and ✕ buttons of row `i` (tests).
func buttons(i: int) -> Array[RailButton]:
	var out: Array[RailButton] = []
	if i < 0 or i >= get_child_count():
		return out
	for c: Node in get_child(i).get_child(0).get_children():
		if c is RailButton:
			out.append(c)
	return out


func _rebuild(n: int) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_labels.clear()
	for i: int in n:
		var id: int = _ids[i]
		var row: PanelContainer = PanelContainer.new()
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA)
		sb.border_color = Palette.color("accent")
		sb.set_border_width_all(UiTheme.BORDER)
		sb.set_corner_radius_all(UiTheme.RADIUS)
		sb.content_margin_left = UiTheme.TOUCH_GAP
		row.add_theme_stylebox_override("panel", sb)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		row.add_child(line)
		var l: Label = Label.new()
		l.custom_minimum_size.x = TEXT_W
		l.add_theme_font_size_override("font_size", FONT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		_labels.append(l)
		var yes: RailButton = RailButton.make("✓", RailButton.Role.ACCENT)
		yes.name = "Accept"
		yes.pressed.connect(func() -> void: answered.emit(id, true))
		var no: RailButton = RailButton.make("✕")
		no.name = "Decline"
		no.pressed.connect(func() -> void: answered.emit(id, false))
		line.add_child(yes)
		line.add_child(no)
		add_child(row)
