class_name TipsView
extends Control
## Rotating tips (#28, P28-Tips, P28-LoadBar): a topic label (`HELM · NOVICE`), the tip
## in large text, `‹` and `›` at the sides and, while given a progress, a thin bar with a
## status line under the tip. Each tip stays max(MIN_SECONDS, characters / CHARS_PER_SECOND
## + 1 s); a tap on the left half goes back, on the right half forward, and restarts the
## tip's time. The tips come from content/tips/tips.json in the UI language (English when a
## tip has no text in it); `prefer()` puts the player's stations and mode first.
##
## Used as the screen shown while a station's first visit builds (stations/client_shell.gd)
## and as the menu's Tips tab. Opaque by default (`opaque`): it draws the background and
## a still starfield, so it can cover a screen while that screen builds. It keeps its
## content inside the safe area.

## The tip shown changed (forward, back or on its timer).
signal tip_changed(index: int)

const TIPS: String = "res://content/tips/tips.json"
## A tip stays at least this long, in seconds.
const MIN_SECONDS: float = 5.0
## Reading speed: characters per second, plus LEAD_SECONDS to start reading.
const CHARS_PER_SECOND: float = 15.0
const LEAD_SECONDS: float = 1.0
## The text column is at most this wide (the design's 600 px at 844 px wide).
const COLUMN: float = 600.0
## The side buttons' size and the gap between them and the column.
const ARROW: float = 48.0
const ARROW_GAP: float = 16.0
const ARROW_FONT: int = 24
## The tip text's size, and the most lines it takes (one more on a narrow screen).
const TIP_FONT: int = 20
const TIP_LINES: int = 3
## The progress bar's height and its track's opacity.
const BAR_HEIGHT: float = 4.0
const TRACK_ALPHA: float = 0.15
const FILL_ALPHA: float = 0.7
const STARS: int = 90

## Draws the background and the stars (false: drawn over whatever is behind).
var opaque: bool = true
## Moves to the next tip on its own; false holds the tip until a tap.
var autoplay: bool = true
## The shuffle seed (L5 shots and tests fix it); 0 picks one at random.
var shuffle_seed: int = 0

## Every tip as {id, topic, text}, in showing order.
var tips: Array[Dictionary] = []
var index: int = 0
## Seconds the current tip has been shown.
var shown_for: float = 0.0
## The load progress, 0..1; negative hides the bar and the status line.
var progress: float = -1.0

var _topics: Dictionary = {}
var _topic: Label
var _tip: Label
var _status: Label
var _back: Button
var _next: Button
var _bar: Control
var _stars: PackedVector2Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if tips.is_empty():
		load_tips(TranslationServer.get_locale())
	_build()
	_show()
	resized.connect(_layout)
	_layout()


## Reads the tips in `lang` (English for a tip without it) and shuffles them; returns
## how many there are.
func load_tips(lang: String, path: String = TIPS) -> int:
	var data: Dictionary = read(path)
	_topics = data.get("topics", {})
	tips.clear()
	for t: Dictionary in data.get("tips", []):
		tips.append({"id": t["id"], "topic": t["topic"], "text": text_of(t, lang)})
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if shuffle_seed != 0:
		rng.seed = shuffle_seed
	else:
		rng.randomize()
	for i: int in range(tips.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Dictionary = tips[i]
		tips[i] = tips[j]
		tips[j] = swap
	index = 0
	shown_for = 0.0
	if is_node_ready():
		_show()
	return tips.size()


## content/tips/tips.json as a Dictionary ({} when unreadable).
static func read(path: String = TIPS) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## A tip's text in `lang`, English when it has none.
static func text_of(tip: Dictionary, lang: String) -> String:
	return str(tip.get(lang, tip.get("en", "")))


## How long a tip of this text stays: max(5 s, characters / 15 + 1 s) (P28-Tips).
static func seconds_for(text: String) -> float:
	return maxf(MIN_SECONDS, text.length() / CHARS_PER_SECOND + LEAD_SECONDS)


## Puts the tips of these topics first (a station's id, a mode's topic), keeping the
## shuffled order within each group; the first tip shows.
func prefer(topics: Array[String]) -> void:
	var first: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for t: Dictionary in tips:
		(first if str(t["topic"]) in topics else rest).append(t)
	tips = first + rest
	index = 0
	shown_for = 0.0
	_show()


## Shows the next tip (wrapping round) and restarts its time.
func next() -> void:
	_go(1)


## Shows the previous tip (wrapping round) and restarts its time.
func back() -> void:
	_go(-1)


## The tip shown ({} with no tips).
func current() -> Dictionary:
	return tips[index] if index < tips.size() else {}


## Sets the load progress (0..1) and the status line under the bar; a negative progress
## hides both.
func set_progress(value: float, status: String = "") -> void:
	progress = clampf(value, 0.0, 1.0) if value >= 0.0 else -1.0
	if _status != null:
		_status.text = status
		_status.visible = progress >= 0.0
		_bar.visible = progress >= 0.0
		_bar.queue_redraw()


## Advances the timer by `delta` seconds and moves on when the tip's time is up.
func tick(delta: float) -> void:
	if not autoplay or tips.is_empty():
		return
	shown_for += delta
	if shown_for >= seconds_for(str(current()["text"])):
		next()


## The topic label of a tip: "HELM · NOVICE" style, from tips.json's topic names.
func topic_text(tip: Dictionary) -> String:
	var lang: String = TranslationServer.get_locale()
	var names: Dictionary = _topics.get(str(tip.get("topic", "")), {})
	return text_of(names, lang).to_upper()


func _process(delta: float) -> void:
	tick(delta)


func _go(step: int) -> void:
	if tips.is_empty():
		return
	index = posmod(index + step, tips.size())
	shown_for = 0.0
	_show()
	tip_changed.emit(index)


func _show() -> void:
	if _tip == null or tips.is_empty():
		return
	var tip: Dictionary = current()
	_tip.text = str(tip["text"])
	_topic.text = topic_text(tip)


## A tap or click on the left half goes back, on the right half forward.
func _gui_input(event: InputEvent) -> void:
	var at: Vector2 = Vector2(-1, -1)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			at = mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if not st.pressed:
			at = st.position
	if at.x < 0.0:
		return
	accept_event()
	if at.x < size.x / 2.0:
		back()
	else:
		next()


func _build() -> void:
	clip_contents = true
	_topic = _label("Topic", "CaptionLabel")
	_tip = _label("Tip", "")
	_tip.add_theme_font_size_override("font_size", TIP_FONT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status = _label("Status", "CaptionLabel")
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_back = _arrow("Back", "‹", back)
	_next = _arrow("Next", "›", next)
	set_progress(progress, "")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in STARS:
		_stars.append(Vector2(rng.randf(), rng.randf()))


func _label(node_name: String, variation: String) -> Label:
	var l: Label = Label.new()
	l.name = node_name
	l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _arrow(node_name: String, text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", ARROW_FONT)
	b.pressed.connect(handler)
	add_child(b)
	return b


## The column centred in the safe area: topic, tip (three lines' room), bar, status; the
## arrows beside the tip, or at the column's ends when the screen is too narrow.
func _layout() -> void:
	if _tip == null:
		return
	var safe: Rect2 = Rect2(Vector2.ZERO, size)
	if is_inside_tree():
		var m: Vector4 = SafeArea.margins(self)
		safe = Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)
	var room: float = safe.size.x - 2.0 * (ARROW + 2.0 * ARROW_GAP)
	var narrow: bool = room < 240.0
	var w: float = minf(COLUMN, safe.size.x - 2.0 * ARROW_GAP if narrow else room)
	var lines: int = TIP_LINES + (1 if narrow else 0)
	_tip.max_lines_visible = lines
	var line: float = _tip.get_line_height() + _tip.get_theme_constant("line_spacing")
	var tip_h: float = line * lines
	var topic_h: float = _topic.get_combined_minimum_size().y
	var status_h: float = _status.get_combined_minimum_size().y
	var total: float = topic_h + 8.0 + tip_h + 24.0 + BAR_HEIGHT + 6.0 + status_h
	if narrow:
		total += 16.0 + ARROW
	var x: float = safe.position.x + (safe.size.x - w) / 2.0
	var y: float = safe.position.y + maxf(0.0, (safe.size.y - total) / 2.0)
	_topic.position = Vector2(x, y)
	_topic.size = Vector2(w, topic_h)
	y += topic_h + 8.0
	_tip.position = Vector2(x, y)
	_tip.size = Vector2(w, tip_h)
	var arrow_y: float = y + (tip_h - ARROW) / 2.0
	y += tip_h + 24.0
	_bar.position = Vector2(x, y)
	_bar.size = Vector2(w, BAR_HEIGHT)
	y += BAR_HEIGHT + 6.0
	_status.position = Vector2(x, y)
	_status.size = Vector2(w, status_h)
	y += status_h + 16.0
	for b: Button in [_back, _next]:
		b.size = Vector2(ARROW, ARROW)
	if narrow:
		_back.position = Vector2(x, y)
		_next.position = Vector2(x + w - ARROW, y)
	else:
		_back.position = Vector2(x - ARROW_GAP - ARROW, arrow_y)
		_next.position = Vector2(x + w + ARROW_GAP, arrow_y)
	queue_redraw()


func _draw() -> void:
	if not opaque:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	var star: Color = Palette.color("text")
	for i: int in _stars.size():
		var p: Vector2 = _stars[i] * size
		star.a = 0.25 + 0.5 * float(i % 4) / 3.0
		draw_rect(Rect2(p, Vector2.ONE * (1.0 + float(i % 3 == 0))), star)


func _draw_bar() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(1, 1, 1, TRACK_ALPHA))
	var fill: Color = Palette.color("accent")
	fill.a = FILL_ALPHA
	_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * maxf(progress, 0.0), r.size.y)), fill)
