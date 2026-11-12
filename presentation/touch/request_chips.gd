class_name RequestChips
extends VBoxContainer
## Request chips on a phone's view-top row (#28 follow-up, P28-Common, design 1.3, FT-PAIR-013):
## first the station's own requests to send (ux-13), then one row per chip another station sent
## here, "Helm: Boost · 18 s", with ✓ (accept) and ✕ (decline), and under it what accepting does
## (`effect`, C5). On a phone this top-of-view strip is the only place chips show (the Crew page has
## none, ux-13); a chip that lapses and a partner's shared data are toasts (StationScreen). The rows
## rebuild only when the set changes; the seconds update in place.
##
##     chips.answered.connect(func(id: int, yes: bool) -> void: ctx.intents.answer_chip(id, yes))
##     chips.show_chips([{"id": 4, "text": "Helm: Boost", "left": 18.0, "effect": "..."}])

## ✓ or ✕ on chip `id`.
signal answered(id: int, accept: bool)
## The player tapped the station's own request `index` (show_sends order) to send it.
signal sent(index: int)

const TEXT_W: float = 150.0
const FONT: int = 13

var _keys: Array = []
var _ids: Array[int] = []
var _labels: Array[Label] = []
## The station's own requests, one button each, first in the column (ux-13: on a phone the
## top of the view is the one place for chips, sent and received). A sent one waiting for an
## answer shows its seconds left.
var _sends: HFlowContainer = HFlowContainer.new()
var _send_texts: Array = []


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_sends.name = "Sends"
	_sends.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_sends.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	_sends.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sends.visible = false
	add_child(_sends)


## `sends`: [{text, left (seconds, 0 when not waiting)}], the requests this station can send
## now; empty hides the row (no chips toggle, or none from this station).
func show_sends(sends: Array) -> void:
	var texts: Array = sends.map(func(c: Dictionary) -> String: return str(c["text"]))
	if texts != _send_texts:
		_send_texts = texts
		for b: Node in _sends.get_children():
			_sends.remove_child(b)
			b.queue_free()
		for i: int in texts.size():
			var b: RailButton = RailButton.make(str(texts[i]))
			b.name = "Send_%d" % i
			b.add_theme_font_size_override("font_size", FONT)
			b.pressed.connect(func() -> void: sent.emit(i))
			_sends.add_child(b)
	for i: int in sends.size():
		var left: float = float(sends[i].get("left", 0.0))
		var b: RailButton = _sends.get_child(i) as RailButton
		var text: String = str(texts[i])
		if left > 0.0:
			text = "%s · %d s" % [text, ceili(left)]
		if b.text != text:
			b.text = text
	_sends.visible = not texts.is_empty()
	visible = _sends.visible or not _keys.is_empty()


## The send buttons, in show_sends order (tests).
func send_buttons() -> Array[RailButton]:
	var out: Array[RailButton] = []
	for b: Node in _sends.get_children():
		out.append(b as RailButton)
	return out


## `chips`: [{id, text, left (seconds), effect (optional)}], oldest first.
func show_chips(chips: Array) -> void:
	var keys: Array = []
	var ids: Array[int] = []
	for c: Dictionary in chips:
		keys.append([int(c["id"]), str(c.get("effect", ""))])
		ids.append(int(c["id"]))
	if keys != _keys:
		_keys = keys
		_ids = ids
		_rebuild(chips)
	for i: int in chips.size():
		var text: String = "%s · %d s" % [chips[i]["text"], ceili(float(chips[i]["left"]))]
		if _labels[i].text != text:
			_labels[i].text = text
	visible = _sends.visible or not keys.is_empty()


## The ✓ and ✕ buttons of incoming row `i` (tests).
func buttons(i: int) -> Array[RailButton]:
	var out: Array[RailButton] = []
	if i < 0 or i + 1 >= get_child_count():
		return out
	for c: Node in get_child(i + 1).get_child(0).get_children():
		if c is RailButton:
			out.append(c)
	return out


func _rebuild(chips: Array) -> void:
	for c: Node in get_children():
		if c == _sends:
			continue
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


func _row(border: String) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	# (only the left margin set: the others keep Godot's default)
	var sb: StyleBoxFlat = UiTheme.box("panel", border, -1, -1, UiTheme.OVERLAY_ALPHA)
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
