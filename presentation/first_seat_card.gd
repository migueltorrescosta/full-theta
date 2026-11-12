class_name FirstSeatCard
extends PanelContainer
## The first-3-actions card (C7, ux-15; replaces the 6 s Controls hint and the callout legend,
## amends FT-STN-012 and D185, D369): on a player's first seat at a station, once per client
## and station, the station's three core lesson actions (the first steps of its Shakedown
## track, the D232 core actions first) in the player's device wording: the binding on a
## keyboard or a pad, the touch how-to on a phone or a tablet. A line points to
## Training › Callouts. "Got it" (or the menu key) closes it; the Controls button opens the
## menu's Controls tab, as the old hint's tap did. Settings' "Show first-visit hints again"
## brings it back. It sits at the top of the first-visit stack (ControlsHint).
##
##     var card: FirstSeatCard = FirstSeatCard.show_once(self, ctx.settings, station, device)
##     if card != null:
##         card.controls_requested.connect(func() -> void: help_requested.emit())

## The Controls button.
signal controls_requested

const ACTIONS: int = 3
## The card's widest (px); narrower than its parent on a phone.
const WIDE: float = 440.0
const FONT: int = 15
const STEPS: String = "res://content/training/steps.tres"

## The station it teaches.
var station: String = ""
## The action lines shown (tests).
var lines: Array[String] = []

var _close: Button = Button.new()
var _controls: Button = Button.new()


## Adds the card for `station` to `parent` on its first seat and records the visit; null when
## the visit was seen (or the browser test hooks skip it) or the station has no lesson.
## `device` (IntentTable.KBM or PAD) names the bindings; `touch` uses the touch words.
static func show_once(
	parent: Control,
	settings: ClientSettings,
	for_station: String,
	device: String = "",
	touch: bool = false
) -> FirstSeatCard:
	if for_station == "" or settings.hint_seen(for_station):
		return null
	var text: Array[String] = action_lines(for_station, settings.bindings, device, touch)
	if text.is_empty():
		return null
	settings.mark_hint_seen(for_station)
	settings.save()
	var card: FirstSeatCard = FirstSeatCard.new()
	card.station = for_station
	card.lines = text
	card._build(settings.bindings, device, touch)
	parent.add_child(card)
	return card


## The first ACTIONS steps of the station's Shakedown track, each in the device's words.
static func action_lines(
	for_station: String, bindings: Bindings, device: String, touch: bool
) -> Array[String]:
	var out: Array[String] = []
	var steps: TrainingStepsDef = load(STEPS) as TrainingStepsDef
	if steps == null:
		return out
	for step: TrainingStepDef in steps.track(StringName(for_station)).slice(0, ACTIONS):
		out.append(action_line(for_station, String(step.intent), bindings, device, touch))
	return out


## One action: "Face selection: F" (the bindings, or the Helm radial's route on a pad), or on
## touch the how-to (`firstseat.touch.<intent>` where the lesson's names the drone, else
## the lesson's `train.touch.<station>.<intent>` or `train.touch.<intent>`).
static func action_line(
	for_station: String, intent: String, bindings: Bindings, device: String, touch: bool
) -> String:
	var label: String = TranslationServer.translate(IntentTable.label_key(intent))
	if touch:
		var key: String = "firstseat.touch." + intent
		var own: String = TranslationServer.translate(key)
		var how: String = TrainingBanner.fill_names(own) if own != key else ""
		if how == "":
			how = TrainingBanner.touch_text(for_station, intent)
		if how != "":
			return how
		return label
	var keys: String = BindingText.describe_all(bindings.bindings(intent, device))
	if keys == "":
		keys = BindingText.radial_route(intent, bindings, device)
	return "%s: %s" % [label, keys] if keys != "" else label


func _init() -> void:
	name = "FirstSeatCard"
	theme_type_variation = "Banner"
	mouse_filter = Control.MOUSE_FILTER_STOP
	ControlsHint.join_stack(self, 1)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH


func _build(bindings: Bindings, device: String, touch: bool) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title: Label = _label(tr("firstseat.title") % tr("station." + station), "accent")
	title.name = "Title"
	col.add_child(title)
	for i: int in lines.size():
		var row: Label = _label("%d  %s" % [i + 1, lines[i]], "text")
		row.name = "Action%d" % (i + 1)
		col.add_child(row)
	var callouts: Label = _label(tr("firstseat.callouts"), "text_dim")
	callouts.name = "Callouts"
	col.add_child(callouts)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(buttons)
	var keyed: bool = device != "" and not touch
	_controls.name = "Controls"
	_controls.text = tr("controls.hint")
	if keyed:
		var key: String = BindingText.describe_all(bindings.bindings("overlay", device))
		_controls.text = tr("controls.hint_key") % key
	_controls.pressed.connect(func() -> void: controls_requested.emit())
	_close.name = "GotIt"
	_close.text = tr("firstseat.got_it")
	if keyed:
		var menu: String = BindingText.describe_all(bindings.bindings("menu", device))
		if menu != "":
			_close.text += "  (%s)" % menu
	_close.theme_type_variation = "RailAccentButton"
	_close.pressed.connect(dismiss)
	for b: Button in [_controls, _close]:
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = UiTheme.TOUCH_MIN
		buttons.add_child(b)


func _label(text: String, role: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_color", Palette.color(role))
	return l


## Closes the card.
func dismiss() -> void:
	queue_free()


## The "Got it" and Controls buttons (tests).
func got_it() -> Button:
	return _close


func controls() -> Button:
	return _controls


func _ready() -> void:
	_place()


func _process(_delta: float) -> void:
	_place()


## Under the top bar, under the "turn sideways" banner when it shows; never wider than WIDE.
func _place() -> void:
	var parent: Control = get_parent() as Control
	if parent == null:
		return
	var w: float = minf(WIDE, parent.size.x - 16.0)
	if custom_minimum_size.x != w:
		custom_minimum_size.x = w
	ControlsHint.place_in_stack(self, ControlsHint.TOP + SafeArea.margins(self).y)
	# As tall as its text: wrapped lines settle after the first frames.
	var h: float = get_combined_minimum_size().y
	if offset_bottom - offset_top != h:
		offset_bottom = offset_top + h
