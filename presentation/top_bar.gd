class_name TopBar
extends Control
## The common top bar (FT-STN-001, station-ui §2): ship name, hull, shields, reactor pips,
## the alert chip (letter, shape and colour, FT-STN-006) with its 3-button picker for
## crew (FT-STN-008: Captain and viewers see it read-only), the station name(s) and the
## mission timer. Hull and shields show the STATUS block's absolute values, rounded.

## The player picked an alert level from the chip's picker.
signal alert_picked(level: int)
## The phone's menu button was tapped: the screen asks the shell for the menu (#28).
signal menu_pressed
## A phone's alert chip was tapped by the crew: the screen opens the N/Y/R sheet.
signal alert_sheet_requested

## Bar height before UI scale (px).
const HEIGHT: float = 40.0
## The least width of the first row's free stretch that takes the toasts (notice_rect).
const NOTICE_MIN_WIDTH: float = 220.0
## The goal chip's row under the bar's rows (px): what the crew is trying to do, with progress.
## A phone's bar has no room for the row: its goal is the second line of the timer's cell.
const GOAL_H: float = 20.0
const GOAL_SIZE: int = 13
const CHIP_LETTER_SIZE: int = 12
## The phone timer's width, and its narrower one beside the full-screen icon (a 390 px bar).
const TIMER_WIDTH: float = 48.0
const TIMER_W_NARROW: float = 40.0
## The phone timer cell's text size, and its smaller one beside the full-screen icon when the
## goal line would not fit.
const TIMER_SIZE: int = 14
const TIMER_SIZE_NARROW: int = 12

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
## The phone's bar (#28 follow-up, design 1.2, apply): the menu button, the compact
## status, the station's page tabs, the alert chip and the timer in one row; the ship name
## and Sound move into the menu.
var menu_button: RailButton = RailButton.make("☰")
var glance: StatusGlance = StatusGlance.new()
var tabs: PageTabs = PageTabs.new()
var phone: bool = false
## Full screen, an icon at the right of the bar (D323); shown where the device offers it.
var fullscreen: FullscreenToggle = FullscreenToggle.new()
## The ship this player watches after a handover (its crew's ship is out, D91), or "": the
## bar names it (R24-18): "Watching Heron" in place of the ship name, and on a phone (whose
## bar has no name) the ship in place of the goal under the timer.
var watching: String = "":
	set(value):
		watching = value
		_raw = []
		_shown = []

## The bots on this ship, after the station names (#40 D1: "Weapons: Bot (for Ana)"), or "".
var bots: String = "":
	set(value):
		bots = value
		_raw = []
		_shown = []

var _row: HBoxContainer
## The rows' box: 8 px in from each edge; a phone's row starts at the top edge, so its
## 48 px targets keep UiTheme.TOUCH_GAP above the content under the bar.
var _box: VBoxContainer
## The second row of a narrow bar: hull, shields and reactor (apply).
var _row2: HBoxContainer = HBoxContainer.new()
var _compact: bool = false
## Every control of the row in order, to put them back after the compact row.
var _order: Array[Control] = []
var _goal: Label = Label.new()
## The phone's short goal ("2 foes"), the timer cell's second line.
var _goal_short: String = ""
var _name: Label = Label.new()
var _hull: Label = Label.new()
var _shields: Label = Label.new()
var _pips: Label = Label.new()
var _stations: Label = Label.new()
var _timer: Label = Label.new()
var _phone_row: HBoxContainer = HBoxContainer.new()
var _phone_timer: Label = Label.new()
## The shape beside a banded hull, shields and reactor (BandBadge), by status key.
var _badges: Dictionary = {}
## What show_state last got and last showed, to skip unchanged frames.
var _raw: Array = []
var _shown: Array = []


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 8)
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	_box = rows
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	rows.add_child(row)
	_row = row
	_row2.add_theme_constant_override("separation", 12)
	_row2.size_flags_vertical = SIZE_EXPAND_FILL
	_row2.visible = false
	rows.add_child(_row2)
	_name.add_theme_color_override("font_color", Palette.color("text"))
	chip.flat = true
	chip.custom_minimum_size = Vector2(0.0, HEIGHT - 8.0)
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.pressed.connect(open_alert_picker)
	chip.draw.connect(_draw_chip)
	var spacer: Control = Control.new()
	# (the station names take the free room and trim with an ellipsis when it runs out, so the
	# timer and the sound button stay on screen; the spacer only pushes them right)
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.0
	_stations.size_flags_horizontal = SIZE_EXPAND_FILL
	_stations.clip_text = true
	_stations.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var keyed: Dictionary = {_hull: "hull", _shields: "shields", _pips: "pips_used"}
	for c: Control in [
		_name, _hull, _shields, _pips, chip, _stations, spacer, _timer, sound, fullscreen
	]:
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(c)
		_order.append(c)
		if keyed.has(c):
			var badge: BandBadge = BandBadge.new()
			badge.visible = false
			badge.size_flags_vertical = SIZE_SHRINK_CENTER
			_badges[keyed[c]] = badge
			row.add_child(badge)
			_order.append(badge)
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
	_phone_row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_phone_row.size_flags_vertical = SIZE_EXPAND_FILL
	_phone_row.visible = false
	rows.add_child(_phone_row)
	# The goal chip (C2): one thin line under every form of the bar.
	_goal.name = "Goal"
	_goal.add_theme_font_size_override("font_size", GOAL_SIZE)
	_goal.add_theme_color_override("font_color", Palette.color("text"))
	_goal.custom_minimum_size.y = GOAL_H
	_goal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_goal.clip_text = true
	_goal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goal.mouse_filter = MOUSE_FILTER_IGNORE
	rows.add_child(_goal)
	menu_button.name = "MenuButton"
	menu_button.add_theme_font_size_override("font_size", 20)
	menu_button.tooltip_text = tr("intent.menu")
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	_phone_timer.add_theme_font_size_override("font_size", TIMER_SIZE)
	_phone_timer.add_theme_color_override("font_color", Palette.color("text"))
	_phone_timer.custom_minimum_size.x = TIMER_WIDTH
	_phone_timer.clip_text = true
	_phone_timer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_phone_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for c: Control in [menu_button, glance, tabs, _phone_timer]:
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		_phone_row.add_child(c)
	fullscreen.name = "Fullscreen"
	fullscreen.visibility_changed.connect(_fit_timer)


func _fit_timer() -> void:
	var w: float = TIMER_W_NARROW if fullscreen.visible else TIMER_WIDTH
	var fs: int = TIMER_SIZE
	var second: String = _second_line()
	if second != "":
		# The goal line ("2 foes") is never cut (w5): beside the full-screen icon (a 390 px
		# bar, no room to spare) the cell's text gets smaller first, then the cell widens.
		var font: Font = _phone_timer.get_theme_font("font")
		var need: float = font.get_string_size(second, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if fullscreen.visible and need > w:
			fs = TIMER_SIZE_NARROW
			need = font.get_string_size(second, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		w = maxf(w, ceilf(need))
	_phone_timer.add_theme_font_size_override("font_size", fs)
	_phone_timer.custom_minimum_size.x = w


## The phone timer cell's second line: the watched ship (R24-18), else the short goal.
func _second_line() -> String:
	return watching if watching != "" else _goal_short


## The bar's extra height for the goal row: none on a phone.
func goal_height() -> float:
	return 0.0 if phone else GOAL_H


## Shows the goal chip: `text` ("Goal: stop the hostiles (2 left)") in its row, `short` ("2 foes")
## under a phone's timer; "" leaves them blank.
func show_goal(text: String, short: String = "") -> void:
	_goal.text = text
	_goal_short = short


## Lays the bar out for the screen's form (R13-15, one call in place of two order-dependent
## setters): a phone's one row (design 1.2: menu, status, tabs, alert chip, timer; the ship
## name and Sound move into the menu, the labels read at 13 px), else one row, or `two_rows`
## with hull, shields and reactor on the second (D195). `height` is one row's; at more than
## HEIGHT the chip and Sound are that tall (tap targets).
func apply(form: LayoutMode.Form, two_rows: bool, height: float = HEIGHT) -> void:
	var on_phone: bool = LayoutMode.is_phone(form)
	_rows_for(two_rows and not on_phone, height, on_phone)
	_phone_for(on_phone, height)


func _phone_for(on: bool, height: float) -> void:
	var size_now: Vector2 = Vector2(UiTheme.TOUCH_PRIMARY, height - 8.0)
	menu_button.custom_minimum_size = size_now
	if on:
		chip.custom_minimum_size = size_now
	if on == phone:
		return
	phone = on
	_box.offset_top = 0.0 if on else 8.0
	_row.visible = not on
	_goal.visible = not on
	_phone_row.visible = on
	if on:
		chip.reparent(_phone_row, false)
		_phone_row.move_child(chip, _phone_row.get_child_count() - 2)
		chip.text = ""
		fullscreen.reparent(_phone_row, false)
	else:
		chip.reparent(_row, false)
		_row.move_child(chip, _order.find(chip))
		fullscreen.reparent(_row, false)
		_row.move_child(fullscreen, _order.find(fullscreen))
	_raw = []
	_shown = []
	chip.queue_redraw()


func _rows_for(compact: bool, height: float, small: bool) -> void:
	chip.custom_minimum_size = Vector2(0.0, height - 8.0)
	sound.custom_minimum_size = Vector2(0.0, height - 8.0) if height > HEIGHT else Vector2.ZERO
	_row.add_theme_constant_override("separation", 10 if compact else 18)
	_stations.visible = not small
	for l: Label in [_name, _hull, _shields, _pips, _stations, _timer]:
		if small:
			l.add_theme_font_size_override("font_size", 13)
		else:
			l.remove_theme_font_size_override("font_size")
	if compact == _compact:
		return
	_compact = compact
	_row2.visible = compact
	var second: Array[Control] = []
	for c: Control in _order:
		if c == _hull or c == _shields or c == _pips or c in _badges.values():
			second.append(c)
	for c: Control in _order:
		var target: HBoxContainer = _row2 if compact and c in second else _row
		if c.get_parent() != target:
			c.reparent(target, false)
	for i: int in _order.size():
		var c: Control = _order[i]
		c.get_parent().move_child(c, -1)


## Refreshes every field, unless nothing shown changed. status: the STATUS block ({}
## before the first snapshot); stations: functional station ids (translated as
## "station.<id>"); in a joint view the focused one is starred (§5.9 wireframes:
## "ENG*+SCI").
func show_state(
	ship_name: String,
	status: Dictionary,
	alert: int,
	stations: Array,
	mission_time: float,
	focused: String = "",
	maxes: Dictionary = {},
	summaries: Dictionary = {}
) -> void:
	# The raw inputs first: between two snapshots nothing is formatted or translated (R20-13).
	var raw: Array = [
		ship_name,
		status,
		alert,
		stations,
		int(mission_time),
		focused,
		maxes,
		summaries,
		_goal_short
	]
	if raw == _raw:
		return
	_raw = raw.duplicate(true)
	var hull: String = _text(status, "hull", summaries, float(maxes.get("hull", 0.0)))
	var shields: String = _text(status, "shields", summaries, float(maxes.get("shields", 0.0)))
	var pips: String = _text(status, "pips_used", summaries)
	# Then what shows: a hull that moved less than the bar's rounding changes no label.
	var state: Array = [ship_name, hull, shields, pips, alert, _raw[3], _raw[7], _raw[4], focused]
	state.append(_goal_short)
	if state == _shown:
		return
	_shown = state
	_name.text = ship_name if watching == "" else tr("topbar.watching") % watching
	_hull.text = tr("topbar.hull") % hull
	_shields.text = tr("topbar.shields") % shields
	_pips.text = tr("topbar.reactor") % pips
	# A cell the station cannot see is left out, not shown as a dash that reads as zero.
	var absent: String = tr("topbar.absent")
	_shields.visible = shields != absent
	_pips.visible = pips != absent
	for key: String in _badges:
		var band: int = summaries.get(key, {}).get("band", -1)
		(_badges[key] as BandBadge).visible = band >= 0
		if band >= 0:
			(_badges[key] as BandBadge).set_band(band as HealthBand.Band)
	alert_style = Palette.alert(alert)
	chip.text = "" if phone else "       " + tr(alert_style["key"])
	chip.add_theme_color_override("font_color", Palette.color(alert_style["role"]))
	chip.add_theme_color_override("font_hover_color", Palette.color(alert_style["role"]))
	chip.queue_redraw()
	var names: PackedStringArray = []
	for s: Variant in stations:
		var star: bool = stations.size() > 1 and str(s) == focused
		names.append(tr(StationCatalogue.name_key(str(s))) + ("*" if star else ""))
	_stations.text = " + ".join(names) + ("   ·   " + bots if bots != "" else "")
	var secs: int = int(mission_time)
	_timer.text = "%02d:%02d" % [secs / 60, secs % 60]
	var second: String = _second_line()
	_phone_timer.text = _timer.text if second == "" else "%s\n%s" % [_timer.text, second]
	_fit_timer()
	glance.set_values(
		_fill(status, "hull", summaries, float(maxes.get("hull", 0.0))),
		hull.trim_suffix("%"),
		_fill(status, "shields", summaries, float(maxes.get("shields", 0.0))),
		shields.trim_suffix("%"),
		pips,
		shields != absent,
		pips != absent
	)


## A status value's share of its maximum for the phone's bars, or -1 (no maximum, or a
## summary hides the value).
static func _fill(
	status: Dictionary, key: String, summaries: Dictionary, max_value: float
) -> float:
	if summaries.has(key) or max_value <= 0.0 or not status.has(key):
		return -1.0
	return float(status[key]) / max_value


## Where a toast or the critical banner shows on a desktop or a tablet (C5): the free stretch
## of the first row between the station names and the timer, so the ship's name, hull, shields
## and power stay in view; status_rect() where that stretch is under NOTICE_MIN_WIDTH.
func notice_rect() -> Rect2:
	if not phone and _stations.is_visible_in_tree() and _timer.is_visible_in_tree():
		var row: Rect2 = _row.get_global_rect()
		var left: float = _stations.get_global_rect().end.x + 12.0
		var right: float = _timer.get_global_rect().position.x - 12.0
		if right - left >= NOTICE_MIN_WIDTH:
			return Rect2(left, row.position.y, right - left, row.size.y)
	return status_rect()


## The box (global coordinates) of the bar's status text, which a toast replaces: the
## phone's glance; else the ship name and the status up to the alert chip (the status row
## alone when it sits on the second row), above the bar's divider line. It holds no control.
func status_rect() -> Rect2:
	var box: Rect2
	if phone:
		box = glance.get_global_rect()
	elif _compact:
		box = _row2.get_global_rect()
	else:
		var row: Rect2 = _row.get_global_rect()
		var left: float = _name.get_global_rect().position.x
		box = Rect2(
			left, row.position.y, chip.get_global_rect().position.x - 8.0 - left, row.size.y
		)
	# The bar keeps its divider line along the bottom edge.
	var bottom: float = get_global_rect().end.y - 1.0
	return box.intersection(Rect2(box.position, Vector2(box.size.x, bottom - box.position.y)))


## Opens the alert picker (Alt+A cycles instead; this is the chip click). Does nothing
## for the Captain and viewers (FT-STN-008).
func open_alert_picker() -> void:
	if not can_set_alert:
		return
	if phone:
		alert_sheet_requested.emit()
		return
	var at: Vector2 = chip.get_screen_position() + Vector2(0.0, chip.size.y)
	picker.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))
	draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), Palette.color("line_strong"))


## The chip's shape with its letter (colour is never the only code, FT-STN-006).
func _draw_chip() -> void:
	var c: Vector2 = Vector2(chip.size.x / 2.0 if phone else 16.0, chip.size.y / 2.0)
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
