## Tablet touch-control mockups for Helm and Weapons (#32, groundwork; throwaway branch).
## station_shot.gd's screen with an option's controls added, set from a shots manifest:
##   option "A": the phone layout scaled up (LayoutMode forced to phone, UI scale `phone_scale`);
##   option "B": today's tablet layout with overlay thumb rails at the screen edges;
##   option "C": docked thumb rails at both edges with the full tablet screen between.
## B and C build their rails from the real touch widgets (RailButton, VirtualStick,
## ThrottleSlider) wired through TouchIntents to the keyboard's intent ids, so TapAudit
## measures them. The report (`audit` path) has the rails' TapAudit result, the rails'
## gaps to the screen's own targets, and the reach of the stick and FIRE to the lower corners
## in CSS px. The thumb reach (120 px) is drawn at the lower corners.
extends "res://tests/visual/station_shot.gd"

const RAIL_W: float = 176.0
const REACH: float = 120.0
## Upright, option C docks both rails along the bottom (side rails would leave the screen
## 468 px): each is 410 px wide and DOCK_H tall.
const DOCK_W: float = 410.0
const DOCK_H: float = 300.0

## "A", "B" or "C".
var option: String = "A"
## A's UI scale (the phone layout px are this many CSS px).
var phone_scale: float = 1.5

var _station: String = "helm"
var _rails: Control = null
var _touch: TouchIntents = null


func _ready() -> void:
	_station = entry
	phone = option == "A"
	touch = option != "A"
	ui_scale = phone_scale if option == "A" else 1.0
	insets = [0, 0, 0, 24]
	var report: String = audit
	audit = ""
	super()
	_touch = TouchIntents.new(_ctx.matcher, func(_e: Dictionary) -> void: pass)
	if option != "A":
		_build_rails()
		_place_rails()
	var shade: ReachShade = ReachShade.new()
	shade.radius = REACH / ui_scale
	shade.band = SafeArea.tap_band(self)
	add_child(shade)
	if report != "":
		_report_later.call_deferred(report)


## The report once the rails have settled (the capture waits only a few frames).
func _report_later(path: String) -> void:
	for i: int in 3:
		await get_tree().process_frame
	_write_report(path)


func _screen_node() -> StationScreen:
	for c: Node in find_children("*", "StationScreen", true, false):
		return c as StationScreen
	return null


func _build_rails() -> void:
	_rails = Control.new()
	_rails.name = "MockRails"
	_rails.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var docked: bool = option == "C"
	var left: TouchRail = TouchRail.new(SIDE_LEFT, docked)
	var right: TouchRail = TouchRail.new(SIDE_RIGHT, docked)
	left.name = "RailL"
	right.name = "RailR"
	left.custom_minimum_size.x = _rail_w()
	right.custom_minimum_size.x = _rail_w()
	if _station == "helm":
		_helm_rails(left, right)
	else:
		_weapons_rails(left, right)
	_rails.add_child(left)
	_rails.add_child(right)
	add_child(_rails)
	if option == "B" and LayoutMode.portrait(get_viewport().get_visible_rect().size):
		# Upright the disc leaves the lower-left corner to the left rail: it moves right of it.
		var s: StationScreen = _screen_node()
		var pad: Control = Control.new()
		pad.custom_minimum_size.x = RAIL_W + UiTheme.TOUCH_GAP
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s._side.add_child(pad)
		s._side.move_child(pad, 0)


func _rail_w() -> float:
	return DOCK_W if _dock() else RAIL_W


## Rails at the edges: B overlays (bottom-anchored, as tall as their controls), C docks
## full height with the screen between.
func _place_rails() -> void:
	var left: TouchRail = _rails.get_node("RailL")
	var right: TouchRail = _rails.get_node("RailR")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bottom: float = SafeArea.tap_bottom(self)
	var top: float = 56.0
	var w: float = _rail_w()
	var portrait: bool = LayoutMode.portrait(vp)
	if _dock():
		left.size = Vector2(w, DOCK_H)
		left.position = Vector2(0.0, bottom - DOCK_H)
		right.size = Vector2(w, DOCK_H)
		right.position = Vector2(vp.x - w, bottom - DOCK_H)
		var sc: StationScreen = _screen_node()
		sc.offset_bottom = -(vp.y - bottom + DOCK_H)
		return
	if option == "C":
		for r: TouchRail in [left, right]:
			r.position = Vector2(0.0 if r == left else vp.x - w, 0.0)
			r.size = Vector2(w, bottom)
		var s: StationScreen = _screen_node()
		s.offset_left = w
		s.offset_right = -w
		return
	var lh: float = left.custom_minimum_size.y
	var rh: float = right.custom_minimum_size.y
	if portrait:
		lh = maxf(lh, 380.0)
		rh = maxf(rh, 380.0)
	left.size = Vector2(w, lh)
	left.position = Vector2(0.0, bottom - lh)
	right.size = Vector2(w, rh)
	right.position = Vector2(vp.x - w, bottom - rh)
	if top > bottom - lh or top > bottom - rh:
		push_warning("rail taller than the screen")


func _btn(id: String, text: String, role: RailButton.Role = RailButton.Role.PLAIN) -> RailButton:
	var b: RailButton = RailButton.make(text, role)
	b.name = id
	_touch.button(b, id)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HelmTouch.fit_text(b)
	b.resized.connect(HelmTouch.fit_text.bind(b))
	return b


func _dock() -> bool:
	return option == "C" and LayoutMode.portrait(get_viewport().get_visible_rect().size)


func _grid(buttons: Array, columns: int = 2) -> GridContainer:
	var g: GridContainer = GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	g.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	for b: Control in buttons:
		g.add_child(b)
	return g


func _stick(label: String) -> VirtualStick:
	var s: VirtualStick = VirtualStick.new()
	s.label = label
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


func _helm_rails(left: TouchRail, right: TouchRail) -> void:
	var throttle: ThrottleSlider = ThrottleSlider.new()
	throttle.value = 0.8
	throttle.value_changed.connect(func(v: float) -> void: _touch.axis("helm_surge", v))
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(_btn("all_stop", HelmTouch.text("all_stop"), RailButton.Role.DANGER))
	col.add_child(_btn("approach", HelmTouch.text("approach")))
	var turn: VirtualStick = _stick(HelmTouch.text("turn"))
	turn.size_flags_vertical = Control.SIZE_SHRINK_END
	turn.custom_minimum_size = Vector2(112.0, 112.0)
	if _dock():
		turn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_touch.stick(turn, "helm_yaw", "helm_pitch")
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	col.add_child(turn)
	# The stick at the corner, the throttle on its inner side: the thumb rests on the stick.
	var row: HBoxContainer = left.add_row([col, throttle])
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 2.0
	throttle.size_flags_horizontal = Control.SIZE_FILL
	var btns: Array = [
		_btn("face", HelmTouch.text("face")),
		_btn("align", HelmTouch.text("align")),
		_btn("shield_track", HelmTouch.text("shield_track")),
		_btn("dock", HelmTouch.text("dock")),
		_btn("jump", HelmTouch.text("jump")),
		_btn("chase_camera", HelmTouch.text("chase_camera")),
		_btn("decoupled", HelmTouch.text("decoupled")),
	]
	right.add(_grid(btns, 4 if _dock() else 2))
	right.add_spacer()
	var slide: VirtualStick = _stick(HelmTouch.text("slide"))
	slide.size_flags_vertical = Control.SIZE_FILL
	slide.custom_minimum_size.y = 136.0
	_touch.stick(slide, "helm_sway", "helm_heave", 1.0, -1.0)
	right.add(slide)
	if _dock():
		slide.size_flags_horizontal = Control.SIZE_SHRINK_END
		slide.custom_minimum_size.x = 136.0
	left.custom_minimum_size.y = 400.0
	right.custom_minimum_size.y = 4.0 * 56.0 + 136.0 + 40.0
	if _dock():
		left.custom_minimum_size.y = DOCK_H
		right.custom_minimum_size.y = DOCK_H


func _weapons_rails(left: TouchRail, right: TouchRail) -> void:
	var aim: VirtualStick = _stick("Aim")
	_touch.stick(aim, "aim_x", "aim_y")
	var fire: RailButton = RailButton.make("FIRE", RailButton.Role.DANGER)
	fire.name = "Fire"
	_touch.button(fire, "fire")
	fire.custom_minimum_size.y = 104.0
	var mount: RailButton = _btn("mount_next", "1 bow ready", RailButton.Role.ACCENT)
	mount.custom_minimum_size.y = 64.0
	if option == "B":
		left.add(mount)
		left.add_spacer()
		aim.size_flags_vertical = Control.SIZE_FILL
		aim.custom_minimum_size.y = 136.0
		left.add(aim)
		(
			right
			. add(
				_grid(
					[
						_btn("ammo_next", "Ammo ▸"),
						_btn("fire_guided", "Guided"),
						_btn("fire_all", "Fire all"),
						_btn("claim", "Claim"),
					]
				)
			)
		)
		right.add_spacer()
		right.add(fire)
		if _dock():
			fire.size_flags_horizontal = Control.SIZE_SHRINK_END
			fire.custom_minimum_size.x = 200.0
		left.custom_minimum_size.y = 64.0 + 150.0 + 40.0
		right.custom_minimum_size.y = 56.0 + 56.0 + 104.0 + 48.0
	else:
		var mounts: Array = []
		for i: int in 4:
			var m: RailButton = _btn("mount_%d" % (i + 1), "Mount %d" % (i + 1))
			if i == 0:
				m.role = RailButton.Role.ACCENT
			mounts.append(m)
		var extras: Array = [
			_btn("ammo_next", "Ammo ▸"),
			_btn("fire_guided", "Guided"),
			_btn("fire_all", "Fire all"),
			_btn("claim", "Claim"),
		]
		aim.size_flags_vertical = Control.SIZE_FILL
		aim.custom_minimum_size.y = 136.0
		if _dock():
			left.add(_grid(mounts))
			right.add(_grid(extras))
			left.custom_minimum_size.y = DOCK_H
			right.custom_minimum_size.y = DOCK_H
		else:
			for m: Control in mounts:
				left.add(m)
			for e: Control in extras:
				right.add(e)
		left.add_spacer()
		left.add(aim)
		if _dock():
			aim.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			aim.custom_minimum_size.x = 136.0
		right.add_spacer()
		right.add(fire)
		if _dock():
			fire.size_flags_horizontal = Control.SIZE_SHRINK_END
			fire.custom_minimum_size.x = 200.0


## The report: rails' TapAudit result, gaps to the screen's own targets, reach in CSS px.
func _write_report(path: String) -> void:
	var scope: Node = _rails if _rails != null else self
	var mine: Dictionary = TapAudit.check(scope)
	var all: Array[Dictionary] = TapAudit.targets(self)
	var mine_rects: Array[Rect2] = []
	for t: Dictionary in mine["targets"]:
		mine_rects.append(t["rect"])
	var vp: Rect2 = get_viewport().get_visible_rect()
	var out: Dictionary = {
		"option": option,
		"station": _station,
		"viewport_px": [vp.size.x, vp.size.y],
		"css_per_px": ui_scale,
		"rail_targets": mine["targets"].size(),
		"under_min": mine["under_min"],
		"under_primary": mine["under_primary"],
		"in_band": mine["in_band"],
		"outside_safe": mine["outside_safe"],
		"tight": mine["tight"],
		"min_side_css": mine["min_side"] * ui_scale,
		"tight_vs_screen": [],
		"overlaps_screen": [],
		"screen_under_min": [],
		"reach": [],
	}
	for t: Dictionary in all:
		var r: Rect2 = t["rect"]
		var is_mine: bool = false
		for m: Rect2 in mine_rects:
			if m == r:
				is_mine = true
		if is_mine:
			continue
		if _rails != null:
			for m: Rect2 in mine_rects:
				var g: float = TapAudit.gap(m, r)
				if g < 0.0:
					out["overlaps_screen"].append(t["text"])
					break
				if g < UiTheme.TOUCH_GAP - TapAudit.SLACK:
					out["tight_vs_screen"].append(t["text"])
					break
		if minf(r.size.x, r.size.y) < UiTheme.TOUCH_MIN - TapAudit.SLACK:
			out["screen_under_min"].append(t["text"])
	for t: Dictionary in mine["targets"]:
		var txt: String = t["text"]
		if txt.begins_with("stick") or txt == "FIRE" or txt.begins_with("ThrottleSlider"):
			var c: Vector2 = (t["rect"] as Rect2).get_center()
			var a: float = c.distance_to(Vector2(0.0, vp.size.y))
			var b: float = c.distance_to(vp.size)
			out["reach"].append(
				{"target": txt, "css_px_to_nearest_lower_corner": minf(a, b) * ui_scale}
			)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))


## The thumb reach: a translucent quarter disc at each lower corner (and the gesture band).
class ReachShade:
	extends Control
	var radius: float = 120.0
	var band: float = 24.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 90

	func _draw() -> void:
		var tint: Color = Color(1.0, 0.9, 0.2, 0.16)
		var line: Color = Color(1.0, 0.9, 0.2, 0.7)
		for x: float in [0.0, size.x]:
			var c: Vector2 = Vector2(x, size.y)
			draw_circle(c, radius, tint)
			draw_arc(c, radius, 0.0, TAU, 48, line, 2.0)
