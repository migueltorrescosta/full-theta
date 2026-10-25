class_name TopBar
extends Control
## The common top bar (FT-STN-001, station-ui §2): ship name, hull, shields, reactor pips,
## the alert chip (letter, shape and colour, FT-STN-006) with its 3-button picker for
## crew (FT-STN-008: Captain and viewers see it read-only), the station name(s) and the
## mission timer. Hull and shields show the STATUS block's absolute values, rounded.

## The player picked an alert level from the chip's picker.
signal alert_picked(level: int)

## Bar height before UI scale (px).
const HEIGHT: float = 40.0
const CHIP_LETTER_SIZE: int = 11

## Crew only (FT-STN-008).
var can_set_alert: bool = false:
	set(value):
		can_set_alert = value
		chip.tooltip_text = tr("alert.pick") if value else tr("alert.readonly")
## Palette.alert() of the level shown: role, letter, shape, key.
var alert_style: Dictionary = Palette.alert(0)
var chip: Button = Button.new()
var sound: SoundToggle = SoundToggle.new()
var picker: PopupPanel = PopupPanel.new()

var _name: Label = Label.new()
var _hull: Label = Label.new()
var _shields: Label = Label.new()
var _pips: Label = Label.new()
var _stations: Label = Label.new()
var _timer: Label = Label.new()
## The shape beside a banded hull, shields and reactor (BandBadge), by status key.
var _badges: Dictionary = {}
## What show_state last showed, to skip unchanged frames.
var _shown: Array = []


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 8)
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	_name.add_theme_color_override("font_color", Palette.color("text"))
	chip.flat = true
	chip.custom_minimum_size = Vector2(0.0, HEIGHT - 8.0)
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.pressed.connect(open_alert_picker)
	chip.draw.connect(_draw_chip)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	var keyed: Dictionary = {_hull: "hull", _shields: "shields", _pips: "pips_used"}
	for c: Control in [_name, _hull, _shields, _pips, chip, _stations, spacer, _timer, sound]:
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(c)
		if keyed.has(c):
			var badge: BandBadge = BandBadge.new()
			badge.visible = false
			badge.size_flags_vertical = SIZE_SHRINK_CENTER
			_badges[keyed[c]] = badge
			row.add_child(badge)
	for l: Label in [_hull, _shields, _pips, _stations, _timer]:
		l.add_theme_color_override("font_color", Palette.color("text_dim"))
	var buttons: HBoxContainer = HBoxContainer.new()
	for level: int in Palette.ALERTS.size():
		var a: Dictionary = Palette.ALERTS[level]
		var b: Button = Button.new()
		b.text = "%s  %s" % [a["letter"], tr(a["key"])]
		b.add_theme_color_override("font_color", Palette.color(a["role"]))
		b.pressed.connect(_pick.bind(level))
		buttons.add_child(b)
	picker.add_child(buttons)
	add_child(picker)
	can_set_alert = false


## Refreshes every field, unless nothing shown changed. status: the STATUS block ({}
## before the first snapshot); stations: functional station ids (translated as
## "station.<id>"); in a joint view the focused one is starred (§5.9 wireframes:
## "ENG*+SCI").
func show_state(
	ship_name: String,
	status: Dictionary,
	alert: int,
	stations: Array,
	mission_s: float,
	focused: String = "",
	maxes: Dictionary = {},
	summaries: Dictionary = {}
) -> void:
	var hull: String = _text(status, "hull", summaries, float(maxes.get("hull", 0.0)))
	var shields: String = _text(status, "shields", summaries, float(maxes.get("shields", 0.0)))
	var pips: String = _text(status, "pips_used", summaries)
	var state: Array = [ship_name, hull, shields, pips, alert, stations.duplicate()]
	for key: String in _badges:
		state.append(summaries.get(key, {}).get("band", -1))
	state.append_array([int(mission_s), focused])
	if state == _shown:
		return
	_shown = state
	_name.text = ship_name
	_hull.text = tr("topbar.hull") % hull
	_shields.text = tr("topbar.shields") % shields
	_pips.text = tr("topbar.reactor") % pips
	for key: String in _badges:
		var band: int = summaries.get(key, {}).get("band", -1)
		(_badges[key] as BandBadge).visible = band >= 0
		if band >= 0:
			(_badges[key] as BandBadge).set_band(band as HealthBand.Band)
	alert_style = Palette.alert(alert)
	chip.text = "       " + tr(alert_style["key"])
	chip.add_theme_color_override("font_color", Palette.color(alert_style["role"]))
	chip.add_theme_color_override("font_hover_color", Palette.color(alert_style["role"]))
	chip.queue_redraw()
	var names: PackedStringArray = []
	for s: Variant in stations:
		var star: bool = stations.size() > 1 and str(s) == focused
		names.append(tr("station." + str(s)) + ("*" if star else ""))
	_stations.text = " + ".join(names)
	var secs: int = int(mission_s)
	_timer.text = "%02d:%02d" % [secs / 60, secs % 60]


## Opens the alert picker (Alt+A cycles instead; this is the chip click). Does nothing
## for the Captain and viewers (FT-STN-008).
func open_alert_picker() -> void:
	if not can_set_alert:
		return
	var at: Vector2 = chip.get_screen_position() + Vector2(0.0, chip.size.y)
	picker.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))
	draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), Palette.color("line"))


## The chip's shape with its letter (colour is never the only code, FT-STN-006).
func _draw_chip() -> void:
	var c: Vector2 = Vector2(16.0, chip.size.y / 2.0)
	var shape: String = alert_style["shape"]
	var pts: PackedVector2Array = Palette.shape_points(shape, c, 14.0)
	chip.draw_colored_polygon(pts.slice(0, -1), Palette.color(alert_style["role"]))
	var font: Font = chip.get_theme_font("font")
	var letter: String = alert_style["letter"]
	var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_LETTER_SIZE)
	var base: Vector2 = (
		c + Vector2(-sz.x / 2.0, font.get_ascent(CHIP_LETTER_SIZE) - sz.y / 2.0 - 1.0)
	)
	var bg: Color = Palette.color("background")
	chip.draw_string(font, base, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_LETTER_SIZE, bg)


func _pick(level: int) -> void:
	picker.hide()
	alert_picked.emit(level)


## Hull and shields are energies in joules (about 10^8): as a percentage of the ship's
## maximum when `max_value` is known (the spec's "hull 92"), else with a k, M or G suffix
## so the bar never shows "Hull 100000000".
static func _amount(status: Dictionary, key: String, max_value: float) -> String:
	if not status.has(key):
		return "-"
	var v: float = float(status[key])
	if max_value > 0.0:
		return "%d%%" % roundi(100.0 * v / max_value)
	if absf(v) >= 1.0e9:
		return "%dG" % roundi(v / 1.0e9)
	if absf(v) >= 1.0e6:
		return "%dM" % roundi(v / 1.0e6)
	if absf(v) >= 1.0e4:
		return "%dk" % roundi(v / 1.0e3)
	return str(roundi(v))


## A status number, or what a summary replaces it with (the band's word, or a dash). Without
## a summary the value is exact (Captain, Viewer, or the toggle on): an energy for a
## `max_value` of 0 or more (a share of it when above 0), else a plain number.
static func _text(
	status: Dictionary, key: String, summaries: Dictionary, max_value: float = -1.0
) -> String:
	if summaries.has(key):
		return str(summaries[key]["text"])
	if max_value >= 0.0:
		return _amount(status, key, max_value)
	return _num(status, key)


static func _num(status: Dictionary, key: String) -> String:
	return str(roundi(float(status[key]))) if status.has(key) else "-"
