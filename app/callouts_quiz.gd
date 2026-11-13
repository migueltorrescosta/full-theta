class_name CalloutsQuiz
extends PanelContainer
## The Callouts lesson (ux-11, D45, D369): a client-only quiz opened from the Training picker,
## with no server and no sim. It shows a sample callout as the game writes it (CalloutText,
## "H2 · 4 high · mid"), then three quick picks about it: which way (the clock), above or below
## (high, level or low) and how far (close, mid or far). Each pick says at once whether it was
## right. The last one emits `finished`, and the menu ticks the lesson like the others
## (ClientSettings.lessons_done). The callout scheme itself is unchanged (D45).

signal closed
signal finished

const QUESTIONS: int = 3
## The widest the quiz's column gets (px).
const MAX_WIDTH: float = 720.0
## The sample callouts: [label, clock, height (-1 low, 0 level, 1 high), range (m), the
## other two clocks offered]. Each round takes the next one, so a replay reads a new callout.
const SAMPLES: Array[Array] = [
	["H2", 4, 1, 4000.0, [8, 2]],
	["Bravo", 9, -1, 15000.0, [3, 6]],
	["U3", 12, 0, 600.0, [6, 3]],
]
## What the label of each sample means.
const GLOSS: Array[String] = [
	"train.quiz.gloss_hostile", "train.quiz.gloss_mark", "train.quiz.gloss_unknown"
]
const HEIGHTS: Array[String] = ["high", "level", "low"]
const BANDS: Array[String] = ["close", "mid", "far"]

## The sample shown (an index into SAMPLES); open() moves to the next one.
var sample: int = 0
## The question on screen (0 to QUESTIONS - 1), QUESTIONS once all are answered.
var question: int = 0
## Right answers so far.
var right: int = 0

var _box: StyleBoxFlat
var _back: Button
var _title: Label
var _progress: Label
var _chip: Label
var _gloss: Label
var _ask: Label
var _options: GridContainer
var _feedback: Label
var _next: Button
## The option picked for the current question, -1 none yet.
var _picked: int = -1


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = UiTheme.box("panel", "line_strong", 16, 16)
	add_theme_stylebox_override("panel", _box)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	scroll.add_child(root)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	root.add_child(head)
	_back = Button.new()
	_back.name = "Back"
	_back.custom_minimum_size = Vector2(0, UiTheme.TOUCH_PRIMARY)
	_back.pressed.connect(func() -> void: closed.emit())
	head.add_child(_back)
	_title = _label("Title", "HeadingLabel", false)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_progress = _label("Progress", "DimLabel", false)
	head.add_child(_progress)
	# The chip as the radar and the rails write it, in the accent on the panel's focus fill.
	var chip_box: PanelContainer = PanelContainer.new()
	chip_box.name = "Chip"
	chip_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip_box.add_theme_stylebox_override("panel", UiTheme.box("panel_focus", "accent", 16, 8))
	root.add_child(chip_box)
	_chip = _label("Callout", "HeadingLabel", false)
	_chip.add_theme_color_override("font_color", Palette.color("accent"))
	chip_box.add_child(_chip)
	_gloss = _label("Gloss", "DimLabel")
	_gloss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gloss)
	_ask = _label("Question", "HeadingLabel")
	_ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_ask)
	_options = GridContainer.new()
	_options.name = "Options"
	_options.columns = 3
	_options.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_options.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	root.add_child(_options)
	for i: int in 3:
		var b: Button = Button.new()
		b.name = "Option%d" % i
		b.custom_minimum_size = Vector2(0, UiTheme.TOUCH_PRIMARY)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pick.bind(i))
		_options.add_child(b)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	root.add_child(foot)
	_feedback = _label("Feedback", "")
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_feedback)
	_next = Button.new()
	_next.name = "Next"
	_next.custom_minimum_size = Vector2(160, UiTheme.TOUCH_PRIMARY)
	_next.pressed.connect(next)
	foot.add_child(_next)
	refresh()


## Starts the quiz on the next sample callout.
func open(first: bool = false) -> void:
	if not first:
		sample = (sample + 1) % SAMPLES.size()
	question = 0
	right = 0
	_picked = -1
	refresh()


## The sample's callout as the game writes it: "H2 · 4 high · mid".
func callout_text() -> String:
	var s: Array = SAMPLES[sample]
	var local: Vector3 = Callout.direction(int(s[1]), int(s[2])) * float(s[3])
	return CalloutText.callout(str(s[0]), local)


## The three options of the current question, as text, and the index of the right one.
func options() -> Array:
	var s: Array = SAMPLES[sample]
	match question:
		0:
			var clocks: Array = [int(s[1])] + (s[4] as Array)
			clocks.sort()
			var texts: Array = clocks.map(func(c: int) -> String: return tr("train.quiz.clock") % c)
			return [texts, clocks.find(int(s[1]))]
		1:
			var texts: Array = HEIGHTS.map(func(w: String) -> String: return tr("callout." + w))
			return [texts, 1 - int(s[2])]
		_:
			var texts: Array = BANDS.map(func(w: String) -> String: return tr("train.quiz." + w))
			return [texts, BANDS.find(Callout.range_band(float(s[3])))]


## Answers the current question with option `i`: the options lock and the card says whether
## it was right, and the right answer when it was not.
func pick(i: int) -> void:
	if _picked >= 0 or question >= QUESTIONS:
		return
	_picked = i
	if i == int(options()[1]):
		right += 1
	refresh()


## After an answer: the next question, or the end (the lesson is done); at the end, Again
## starts over on the next sample.
func next() -> void:
	if question >= QUESTIONS:
		open()
		return
	if _picked < 0:
		return
	_picked = -1
	question += 1
	if question >= QUESTIONS:
		finished.emit()
	refresh()


func refresh() -> void:
	_back.text = "‹ " + tr("settings.close")
	_title.text = tr("train.picker.callouts")
	_chip.text = callout_text()
	_gloss.text = tr(GLOSS[sample])
	var over: bool = question >= QUESTIONS
	_progress.text = tr("train.quiz.progress") % [mini(question + 1, QUESTIONS), QUESTIONS]
	_options.visible = not over
	if over:
		_ask.text = tr("train.quiz.done") % [right, QUESTIONS]
		_feedback.text = ""
		_next.text = tr("train.quiz.again")
		_next.visible = true
		return
	_ask.text = tr("train.quiz.q%d" % question) % str(SAMPLES[sample][0])
	var opts: Array = options()
	var texts: Array = opts[0]
	for i: int in texts.size():
		var b: Button = _options.get_child(i)
		b.text = texts[i]
		# Answered: the options lock; the right one is lit, a wrong pick shown in warn.
		b.disabled = _picked >= 0
		b.remove_theme_color_override("font_disabled_color")
		if _picked >= 0 and i == int(opts[1]):
			b.add_theme_color_override("font_disabled_color", Palette.color("ok"))
		elif _picked == i:
			b.add_theme_color_override("font_disabled_color", Palette.color("warn"))
	# Next shows only once there is an answer (no button that does nothing).
	_next.visible = _picked >= 0
	_next.text = tr("train.quiz.next") if question < QUESTIONS - 1 else tr("train.quiz.finish")
	if _picked < 0:
		_feedback.text = ""
	elif _picked == int(opts[1]):
		_feedback.text = tr("train.quiz.right")
		_feedback.add_theme_color_override("font_color", Palette.color("ok"))
	else:
		_feedback.text = tr("train.quiz.wrong") % str(texts[int(opts[1])])
		_feedback.add_theme_color_override("font_color", Palette.color("warn"))


## Keeps the quiz inside the safe area; the options stack on a phone held upright.
func fit() -> void:
	if not is_inside_tree():
		return
	var m: Vector4 = SafeArea.margins(self)
	# A wide window keeps the quiz to a readable column.
	var side: float = maxf(16.0, (size.x - MAX_WIDTH) / 2.0)
	_box.content_margin_left = side + m.x
	_box.content_margin_top = 16.0 + m.y
	_box.content_margin_right = side + m.z
	_box.content_margin_bottom = 16.0 + maxf(m.w, SafeArea.tap_band(self))
	var upright: bool = LayoutMode.form_of(self) == LayoutMode.Form.PHONE_PORTRAIT
	_options.columns = 1 if upright else 3


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		fit()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _title != null:
		refresh()


func _label(node_name: String, variation: String, wraps: bool = true) -> Label:
	var l: Label = Label.new()
	l.name = node_name
	l.theme_type_variation = variation
	if wraps:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
