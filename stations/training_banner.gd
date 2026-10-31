class_name TrainingBanner
extends PanelContainer
## The Shakedown's step banner and Next button (FT-MIS-039, D235), shown on every station
## while a training run goes. The server says each station's step as a ship-computer line
## (content/dialogue/shakedown.json); the shell keeps the latest one per station in
## StationContext.training. The banner shows the focused station's step: the line's text
## with the player's current binding, its worked example, and Next. Next sends
## TrainingNextCommand; on a step that ends on a command it does nothing, and a player may
## press it anyway. Next has a key (the training_next intent), a pad chord and a tap.
##
## The wording follows the player's device (D321): on a touch layout (phone, tablet) the
## step reads in touch words from `train.touch.<station>.<intent>` or `train.touch.<intent>`
## (control names in {t:key} are the translated labels of the controls themselves), with no
## key names and no key on Next; a pad in use (D321) gets the pad's buttons, and a keyboard
## the keys, as before. On a touch layout the card also keeps clear of the station's
## controls (D322): it sits where no tap target is, as a card of the step, its how-to and
## Next, or folded to one line, and moves when a page change takes its place.

const LINE_PREFIX: String = "shakedown."
const PAIR_PREFIX: String = "pair_"
## Seconds between two looks for room on a touch layout, and the step of the look (px).
const LOOK_S: float = 0.3
const STEP_PX: float = 8.0
const SETTLE_FRAMES: int = 4
## A radar under this share of the window is a picture the card keeps clear of.
const INSET_SHARE: float = 0.2
## The widths a touch card tries, widest first, and the least.
const WIDTHS: Array[float] = [400.0, 360.0, 320.0, 280.0]
const MIN_WIDTH: float = 240.0
## Station ids of the Shakedown: the six crew stations and the Captain seat.
const STATIONS: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "captain"
]

var ctx: StationContext
## The station whose step shows (the screen's focused station).
var station: String = ""

var _title: Label
var _text: Label
var _example: Label
var _next: Button
var _col: VBoxContainer
var _head: HBoxContainer
var _fold: Button
## The player folded the card to one line (touch layouts).
var _folded: bool = false
## The card is one line because the whole card fits nowhere clear of the controls.
var _squeezed: bool = false
## The card has been placed by `place` (not at its desktop corner).
var _moved: bool = false
## Seconds until the touch card looks for room again.
var _look_in: float = 0.0
## The id of the step the card last placed itself for.
var _placed_for: String = ""
## Frames left in which the card looks for room every frame.
var _settle: int = 0
## What the card last looked for room under (_layout_key).
var _key: Array = []
## The width the card is laid out for (touch layouts).
var _width: float = 400.0


func setup(context: StationContext) -> void:
	ctx = context
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	custom_minimum_size = Vector2(420.0, 0.0)
	# It starts empty, so its offsets are those of an empty box: grow upward from the bottom
	# edge when a step arrives, not off the screen (found with the L5 lesson shot, D303).
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)
	_title = Label.new()
	_title.theme_type_variation = "HeadingLabel"
	_col.add_child(_title)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_col.add_child(_head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(_text)
	_fold = Button.new()
	_fold.name = "Fold"
	_fold.custom_minimum_size = Vector2(UiTheme.TOUCH_PRIMARY, UiTheme.TOUCH_PRIMARY)
	_fold.pressed.connect(_toggle_fold)
	_fold.visible = false
	_head.add_child(_fold)
	_example = Label.new()
	_example.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(_example)
	_next = Button.new()
	_next.name = "Next"
	_next.custom_minimum_size = Vector2(0.0, 52.0)
	_next.pressed.connect(press)
	_col.add_child(_next)
	visible = false


func _process(_delta: float) -> void:
	refresh()


## Shows the focused station's latest step, or hides.
func refresh() -> void:
	var entry: Dictionary = ctx.training.get(station, {})
	visible = not entry.is_empty()
	if not visible:
		return
	var device: String = ctx.matcher.device
	var touch: bool = touch_wording()
	_title.text = tr("train.title")
	_title.visible = not touch
	var text: String = str(entry["text"])
	var example: String = ""
	if touch:
		text = strip_markers(text)
		example = touch_text(station, str(entry.get("intent", "")))
	if example == "":
		var key: String = str(entry.get("example", ""))
		if key != "":
			example = BindingText.fill_markers(tr(key), ctx.settings.bindings, device)
	_text.text = text if touch else BindingText.fill_markers(text, ctx.settings.bindings, device)
	_example.text = example
	var done: bool = bool(entry.get("done", false))
	_next.visible = not done
	if touch:
		_next.text = tr("train.next")
	else:
		_next.text = "%s  (%s)" % [tr("train.next"), _next_binding(device)]
	_set_touch_layout(touch)
	_example.visible = example != "" and not (touch and is_folded())
	if touch:
		var key: Array = _layout_key()
		if key != _key:
			_key = key
			_settle = SETTLE_FRAMES
		var id: String = str(entry.get("line", ""))
		_look_in -= get_process_delta_time()
		if id != _placed_for:
			_placed_for = id
			_settle = SETTLE_FRAMES
		# A new step looks every frame until its text has laid out, then every LOOK_S.
		if _look_in <= 0.0 or _settle > 0:
			_look_in = LOOK_S
			_settle = maxi(_settle - 1, 0)
			place()


## True when the step reads in touch words: a touch layout, unless a pad is in use.
func touch_wording() -> bool:
	if not is_inside_tree() or not LayoutMode.is_touch(LayoutMode.kind_of(self)):
		return false
	return not (
		ctx.matcher.device == IntentTable.PAD and not Input.get_connected_joypads().is_empty()
	)


## `text` without its `{binding:...}` markers (a touch layout has no binding to show).
static func strip_markers(text: String) -> String:
	var re: RegEx = RegEx.create_from_string("\\s*\\{binding:[a-z][a-z0-9_]*\\}")
	return re.sub(text, "", true).strip_edges()


## The touch how-to of a step: `train.touch.<station>.<intent>`, else `train.touch.<intent>`,
## its `{t:key}` names translated; "" when the step has none (a pair step, a finished track).
static func touch_text(for_station: String, intent: String) -> String:
	for key: String in ["train.touch.%s.%s" % [for_station, intent], "train.touch.%s" % intent]:
		var t: String = TranslationServer.translate(key)
		if t != key:
			return fill_names(t)
	return ""


## `text` with each `{t:key}` replaced by the translation of `key`, the words a control wears.
static func fill_names(text: String) -> String:
	if not "{t:" in text:
		return text
	var re: RegEx = RegEx.create_from_string("\\{t:([a-z][a-z0-9_.]*)\\}")
	var out: String = ""
	var at: int = 0
	for m: RegExMatch in re.search_all(text):
		out += text.substr(at, m.get_start() - at)
		out += str(TranslationServer.translate(m.get_string(1)))
		at = m.get_end()
	return out + text.substr(at)


## The fold button and the card's arrangement for a touch layout (or the desktop's).
func _set_touch_layout(touch: bool) -> void:
	_fold.visible = touch
	if touch:
		_fold.text = "▸" if is_folded() else "▾"
		_fold.tooltip_text = tr("train.expand") if is_folded() else tr("train.collapse")
		_next.custom_minimum_size = Vector2(0.0, UiTheme.TOUCH_PRIMARY)
		var width: float = card_width()
		custom_minimum_size.x = width
		# Folded, Next sits in the one line, left of the fold button.
		var want: Node = _head if is_folded() else _col
		if _next.get_parent() != want:
			_next.reparent(want, false)
			if is_folded():
				_head.move_child(_next, _fold.get_index())
			else:
				_col.move_child(_next, _col.get_child_count() - 1)
		_text.autowrap_mode = (
			TextServer.AUTOWRAP_OFF if is_folded() else TextServer.AUTOWRAP_WORD_SMART
		)
		_text.clip_text = is_folded()
		_example.custom_minimum_size.x = width - 24.0
		_text.custom_minimum_size.x = (
			96.0 if is_folded() else width - 24.0 - UiTheme.TOUCH_PRIMARY - 8.0
		)
	else:
		if _moved:
			_moved = false
			set_anchors_and_offsets_preset(
				Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12
			)
		_next.custom_minimum_size = Vector2(0.0, 52.0)
		custom_minimum_size.x = 420.0
		if _next.get_parent() != _col:
			_next.reparent(_col, false)
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.clip_text = false


## The card's width on a touch layout (px): about 380, less on a narrow window.
func card_width() -> float:
	var room: Rect2 = SafeArea.tap_rect(self)
	return minf(_width, maxf(room.size.x - 2.0 * UiTheme.TOUCH_GAP, MIN_WIDTH))


## True when the card shows one line: folded by the player, or squeezed for room.
func is_folded() -> bool:
	return _folded or _squeezed


func _toggle_fold() -> void:
	_folded = not _folded
	_look_in = 0.0
	_settle = SETTLE_FRAMES


## Puts the card where no tap target of the screen is (D322): the highest free spot, centred
## first, then at the left or the right; folded to one line when the whole card fits
## nowhere. Targets and the rotate banner count as taken, with the touch gap around them.
## Returns the card's rectangle (viewport px).
func place() -> Rect2:
	var screen: Control = get_parent() as Control
	var room: Rect2 = SafeArea.tap_rect(self)
	var taken: Array[Rect2] = []
	for t: Dictionary in TapAudit.targets(screen, self):
		taken.append((t["rect"] as Rect2).grow(UiTheme.TOUCH_GAP))
	_add_pickers(screen, taken)
	var banner: Variant = screen.get("rotate_banner")
	if banner is Control and (banner as Control).is_visible_in_tree():
		taken.append((banner as Control).get_global_rect())
	var size_now: Vector2 = Vector2.ZERO
	var spot: Variant = null
	# The whole card first, at the widest width that finds room; else one line.
	for squeeze: bool in [false, true]:
		if squeeze and _folded:
			break
		_squeezed = squeeze
		for w: float in WIDTHS:
			_width = w
			size_now = _arrange()
			spot = _free_spot(room, taken, size_now)
			if spot != null:
				break
		if spot != null:
			break
	var at: Vector2 = spot if spot != null else Vector2(room.position.x, room.end.y - size_now.y)
	_moved = true
	size = size_now
	global_position = at
	return Rect2(at, size_now)


## Adds the rectangles of the pictures a finger taps (the radar, the shield ring), which are
## not buttons, under `node`, with the touch gap around them.
func _add_pickers(node: Node, taken: Array[Rect2]) -> void:
	if node == self:
		return
	var c: Control = node as Control
	if c != null and not c.is_visible_in_tree():
		return
	if c is ShieldRing or (c is DiscRadar and _is_inset(c)):
		taken.append(c.get_global_rect().grow(UiTheme.TOUCH_GAP))
		return
	for ch: Node in node.get_children():
		if not ch is Window:
			_add_pickers(ch, taken)


## True for a radar that is a small picture (an inset, a rail's disc), not the station's view.
func _is_inset(c: Control) -> bool:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return c.get_global_rect().get_area() < INSET_SHARE * vp.x * vp.y


## What a new look for room depends on besides time: the window, the focused panel and its page.
func _layout_key() -> Array:
	var screen: Object = get_parent()
	var panel: Variant = (
		screen.call("focused_panel") if screen.has_method("focused_panel") else null
	)
	var pages: Variant = (panel as Object).get("pages") if panel != null else null
	return [
		get_viewport().get_visible_rect().size,
		station,
		pages.get_instance_id() if pages != null else 0,
		(pages as PageHost).current if pages != null else -1,
	]


## Lays the card out for its fold and returns its size.
func _arrange() -> Vector2:
	_set_touch_layout(true)
	_example.visible = _example.text != "" and not is_folded()
	reset_size()
	return Vector2(card_width(), maxf(get_combined_minimum_size().y, 1.0))


## The highest spot of `size_now` inside `room` clear of `taken` (the current one while it
## is still free), or null.
func _free_spot(room: Rect2, taken: Array[Rect2], size_now: Vector2) -> Variant:
	var now: Rect2 = Rect2(global_position, size_now)
	if _moved and room.encloses(now) and _clear(now, taken):
		return global_position
	var xs: Array[float] = [
		room.position.x + (room.size.x - size_now.x) / 2.0,
		room.position.x + UiTheme.TOUCH_GAP,
		room.end.x - size_now.x - UiTheme.TOUCH_GAP,
	]
	var y: float = room.position.y
	while y + size_now.y <= room.end.y + 0.5:
		for x: float in xs:
			if _clear(Rect2(x, y, size_now.x, size_now.y), taken):
				return Vector2(x, y)
		y += STEP_PX
	return null


static func _clear(r: Rect2, taken: Array[Rect2]) -> bool:
	for t: Rect2 in taken:
		if t.intersects(r):
			return false
	return true


## Sends Next for the focused station (false when no step is showing).
func press() -> bool:
	if not visible or station == "":
		return false
	ctx.intents.command({"kind": "training_next", "station": station})
	return true


func _next_binding(device: String) -> String:
	return BindingText.describe_all(ctx.settings.bindings.bindings("training_next", device))


## Records a shakedown subtitle (a voice_line payload as SubtitleFeed keeps it) in
## `training`: station -> {"line", "intent", "text", "example", "done"}. The line id says
## whose it is (shakedown.<station>.<intent>, shakedown.pair_pN for a pair's two stations,
## shakedown.all_done for everyone). Other lines are ignored.
static func note(training: Dictionary, entry: Dictionary, pair_stations: Callable) -> void:
	var line: String = str(entry.get("line", ""))
	if not line.begins_with(LINE_PREFIX):
		return
	var rest: PackedStringArray = line.trim_prefix(LINE_PREFIX).split(".")
	var who: Array[String] = []
	var intent: String = ""
	var done: bool = false
	if rest.size() == 1 and rest[0] == "all_done":
		who.assign(STATIONS)
		done = true
	elif rest.size() == 1 and rest[0].begins_with(PAIR_PREFIX):
		who.assign(pair_stations.call(rest[0]))
		intent = rest[0]
	elif rest.size() == 2 and STATIONS.has(rest[0]):
		who.append(rest[0])
		intent = rest[1]
		done = intent == "track_done"
	for s: String in who:
		training[s] = {
			"line": line,
			"intent": intent,
			"text": str(entry.get("text", "")),
			"example": "" if done else "train.ex." + intent,
			"done": done,
		}
