class_name HelmTouch
extends Control
## Helm's phone layouts (#28, FT §5.1 touch, D195): the touch controls over the cockpit.
## Touch changes the arrangement only: every control fires the Helm intent its key or
## button fires (TouchIntents), so the panel's commands are the same.
##
## Landscape (owner pick C, rails plus tabs and drawers): overlay rails over the full view.
## Left: throttle, All stop, Approach, Radar (a drawer with the disc radar) and the Turn
## stick (attitude). Right: a Nav tab (Face, Align, Dock, Jump) and a Shield tab (Track; the
## shield ring opens in a drawer beside the rail while the tab is open), then the Slide
## stick (translation).
##
## Portrait (owner pick A): the view on top and one block of controls below it: throttle,
## Turn / Slide (what the one stick does), All stop, the stick, and Approach, Face, Align,
## Track, Dock, Jump and Radar; the screen's banner asks to turn sideways.
##
## The throttle sets the speed setpoint, as the spec's assist-only touch throttle: while the
## slider differs from the HELM block's setpoint, it feeds helm_surge (the S/W and trigger
## axis) until the setpoint gets there, then shows the setpoint again (All stop, Approach,
## the keyboard).

## Rail widths and the portrait block's height (the mockups).
const LEFT_W: float = 176.0
const RIGHT_W: float = 136.0
const BLOCK_H: float = 300.0
## Drawer widths: the radar's chips need more than the default.
const RADAR_DRAWER_W: float = 300.0
## Shield ring side over the portrait view.
const RING_PORTRAIT: float = 140.0
## The portrait grid's text size (its columns are about 90 px).
const PORTRAIT_FONT: int = 15
## The throttle stops feeding helm_surge within this many m/s of its setpoint; the input is
## the gap over GAIN_S seconds of full ramp.
const SETPOINT_TOLERANCE: float = 1.0
const GAIN_S: float = 0.5
## The controls' English texts until content/i18n/strings.json has their "touch.helm.*" keys.
const TEXTS: Dictionary = {
	"all_stop": "All stop",
	"approach": "Approach",
	"radar": "Radar ▸",
	"radar_title": "Radar",
	"turn": "Turn",
	"slide": "Slide",
	"nav": "Nav",
	"shield": "Shield",
	"shield_title": "Shields",
	"face": "Face",
	"align": "Align",
	"dock": "Dock",
	"jump": "Jump",
	"shield_track": "Track",
}
## The portrait banner's text (StationScreen.rotate_banner).
const ROTATE_KEY: String = "touch.rotate_helm"
const ROTATE_TEXT: String = "Turn sideways for the full Helm"
## Tabs of the right rail.
const TAB_NAV: int = 0
const TAB_SHIELD: int = 1

var panel: HelmPanel
var portrait: bool = false
var touch: TouchIntents
## The intent each Helm button fires: id -> RailButton.
var buttons: Dictionary = {}
var throttle: ThrottleSlider
## Landscape: the two sticks; portrait: `turn` is the one stick and `slide` is null.
var turn: VirtualStick
var slide: VirtualStick
## Portrait: what the one stick drives.
var stick_slides: bool = false
var mode_turn: RailButton
var mode_slide: RailButton
var tabs: TouchTabs
var radar: DiscRadar
var drawer: TouchDrawer
## Landscape: the drawer the shield ring moves into while the Shield tab is open.
var ring_drawer: TouchDrawer
var layout: RailLayout
## Portrait: the block of controls under the view.
var block: PanelContainer

## The setpoint the throttle asks for (share of speed_max), NAN while it shows the setpoint.
var _target: float = NAN


func _init(p_panel: HelmPanel, sink: Callable, is_portrait: bool) -> void:
	panel = p_panel
	portrait = is_portrait
	name = "HelmTouch"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch = TouchIntents.new(panel.ctx.matcher, sink)
	throttle = ThrottleSlider.new()
	throttle.value_changed.connect(_on_throttle)
	var assist: AssistDef = _assist()
	if assist != null and assist.speed_max > 0.0:
		throttle.min_value = assist.speed_min / assist.speed_max
	radar = DiscRadar.new()
	radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radar.gui_input.connect(_on_radar_input)
	if portrait:
		_build_portrait()
	else:
		_build_landscape()


## A rail button for a Helm intent, wired to it.
func _button(id: String, role: RailButton.Role = RailButton.Role.PLAIN) -> RailButton:
	var b: RailButton = RailButton.make(text(id), role)
	b.name = id
	touch.button(b, id)
	buttons[id] = b
	return b


func _build_landscape() -> void:
	layout = RailLayout.new()
	add_child(layout)
	# The rails start a gap below the top bar's buttons (8 px between targets).
	layout.offset_top = UiTheme.TOUCH_GAP
	var left: TouchRail = layout.rail(SIDE_LEFT)
	left.custom_minimum_size.x = LEFT_W
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(_button("all_stop", RailButton.Role.DANGER))
	col.add_child(_button("approach"))
	var opener: RailButton = RailButton.make(text("radar"))
	opener.name = "radar"
	col.add_child(opener)
	turn = _stick("turn")
	touch.stick(turn, "helm_yaw", "helm_pitch")
	turn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(turn)
	var row: HBoxContainer = left.add_row([throttle, col])
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	throttle.size_flags_horizontal = Control.SIZE_FILL
	drawer = layout.add_drawer(TouchDrawer.new(text("radar_title"), SIDE_LEFT))
	drawer.custom_minimum_size.x = RADAR_DRAWER_W
	drawer.body.add_child(radar)
	drawer.bind_opener(opener)
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RIGHT_W
	tabs = TouchTabs.new()
	tabs.add_tab(text("nav"), _grid(["face", "align", "dock", "jump"]))
	tabs.add_tab(text("shield"), _grid(["shield_track"]))
	tabs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add(tabs)
	right.add_spacer()
	slide = _stick("slide")
	# Right stick: x strafes to starboard, up lifts (the pad's RS_X and -RS_Y).
	touch.stick(slide, "helm_sway", "helm_heave", 1.0, -1.0)
	right.add(slide)
	ring_drawer = layout.add_drawer(TouchDrawer.new(text("shield_title"), SIDE_RIGHT))
	tabs.tab_changed.connect(
		func(i: int) -> void:
			if i == TAB_SHIELD:
				ring_drawer.open()
			else:
				ring_drawer.close()
	)
	ring_drawer.toggled.connect(
		func(open: bool) -> void:
			if not open and tabs.current == TAB_SHIELD:
				tabs.current = TAB_NAV
	)
	layout.content_rect_changed.connect(func(_r: Rect2) -> void: panel.hud.queue_redraw())


func _build_portrait() -> void:
	block = PanelContainer.new()
	block.theme_type_variation = "DockedRail"
	block.add_to_group(TouchInput.GROUP)
	block.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	block.offset_top = -BLOCK_H
	add_child(block)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	block.add_child(row)
	row.add_child(throttle)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.4
	row.add_child(col)
	var modes: HBoxContainer = HBoxContainer.new()
	modes.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(modes)
	var group: ButtonGroup = ButtonGroup.new()
	mode_turn = RailButton.make(text("turn"))
	mode_slide = RailButton.make(text("slide"))
	for b: RailButton in [mode_turn, mode_slide]:
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
	mode_turn.name = "mode_turn"
	mode_slide.name = "mode_slide"
	mode_turn.button_pressed = true
	mode_turn.pressed.connect(set_stick_slides.bind(false))
	mode_slide.pressed.connect(set_stick_slides.bind(true))
	col.add_child(_button("all_stop", RailButton.Role.DANGER))
	turn = _stick("turn")
	turn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	turn.moved.connect(_on_one_stick)
	turn.name = "stick"
	col.add_child(turn)
	var grid: GridContainer = _grid(["approach", "face", "align", "shield_track", "dock", "jump"])
	# Narrow columns: a smaller text keeps "Approach" whole.
	for b: Control in grid.get_children():
		b.add_theme_font_size_override("font_size", PORTRAIT_FONT)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_stretch_ratio = 2.0
	var opener: RailButton = RailButton.make(text("radar"))
	opener.name = "radar"
	opener.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opener.add_theme_font_size_override("font_size", PORTRAIT_FONT)
	grid.add_child(opener)
	row.add_child(grid)
	drawer = TouchDrawer.new(text("radar_title"), SIDE_LEFT)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.offset_bottom = -BLOCK_H - UiTheme.TOUCH_GAP
	drawer.offset_left = UiTheme.TOUCH_GAP
	drawer.offset_right = -UiTheme.TOUCH_GAP
	drawer.offset_top = UiTheme.TOUCH_GAP
	drawer.body.add_child(radar)
	add_child(drawer)
	drawer.bind_opener(opener)


## A two-column grid of rail buttons for Helm intents.
func _grid(ids: Array) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	for id: String in ids:
		var b: RailButton = _button(id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	return grid


func _stick(key: String) -> VirtualStick:
	var s: VirtualStick = VirtualStick.new()
	s.label = text(key)
	return s


## The text of control `key`: "touch.helm.<key>" translated, else TEXTS.
static func text(key: String) -> String:
	return TouchText.of("touch.helm." + key, TEXTS[key])


## Portrait: the one stick turns (false) or slides (true); switching lets go of the other.
func set_stick_slides(on: bool) -> void:
	stick_slides = on
	turn.label = text("slide" if on else "turn")
	mode_turn.set_pressed_no_signal(not on)
	mode_slide.set_pressed_no_signal(on)
	_on_one_stick(turn.value)


func _on_one_stick(v: Vector2) -> void:
	var t: Vector2 = Vector2.ZERO if stick_slides else v
	var s: Vector2 = v if stick_slides else Vector2.ZERO
	touch.axis("helm_yaw", t.x)
	touch.axis("helm_pitch", t.y)
	touch.axis("helm_sway", s.x)
	touch.axis("helm_heave", -s.y)


## The part of the view no control covers, in `control`'s coordinates (the HUD keeps its
## read-outs inside it).
func content_rect_in(control: Control) -> Rect2:
	if layout != null:
		return layout.content_rect_in(control)
	var xf: Transform2D = control.get_global_transform().affine_inverse() * get_global_transform()
	return xf * Rect2(Vector2.ZERO, Vector2(size.x, maxf(size.y - BLOCK_H, 0.0)))


## The view's height above the portrait block (the 3D view and the HUD stop there).
func view_bottom_inset() -> float:
	return BLOCK_H if portrait else 0.0


## Every frame: the throttle and the ring.
func update(ring: ShieldRing) -> void:
	_drive_throttle()
	radar.set_picture(panel.ctx.picture(), panel.ctx.crew.selection)
	_place_ring(ring)


## Landscape: the ring lives in the Shield drawer; portrait: at the top right of the view.
## HelmPanel takes it back when the layout goes.
func _place_ring(ring: ShieldRing) -> void:
	if portrait:
		# No caption: the view is small; the ring keeps clear of the thrust read-out.
		var free: Rect2 = content_rect_in(panel)
		ring.label = false
		ring.size = Vector2(RING_PORTRAIT, RING_PORTRAIT)
		ring.position = Vector2(free.end.x - ring.size.x - 4.0, free.position.y + 4.0)
		return
	if ring.get_parent() != ring_drawer.body:
		ring.reparent(ring_drawer.body, false)
		ring.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _assist() -> AssistDef:
	var def: ShipDef = panel.ctx.ship_def()
	return def.assist if def != null else null


func _on_throttle(v: float) -> void:
	_target = v


## While the slider asks for another setpoint, helm_surge ramps toward it (assist only);
## otherwise the slider shows the setpoint.
func _drive_throttle() -> void:
	var assist: AssistDef = _assist()
	var h: Dictionary = panel.helm_block()
	if assist == null or assist.speed_max <= 0.0:
		return
	var setpoint: float = float(h.get("throttle_setpoint", 0.0))
	var holds: bool = (
		bool(h.get("decoupled", false))
		or bool(h.get("all_stop", false))
		or panel.ctx.matcher.is_held("approach")
	)
	if not is_nan(_target) and not holds:
		var gap: float = _target * assist.speed_max - setpoint
		if absf(gap) > SETPOINT_TOLERANCE:
			touch.axis("helm_surge", clampf(gap / (assist.speed_ramp * GAIN_S), -1.0, 1.0))
			return
	if not is_nan(_target):
		touch.axis("helm_surge", 0.0)
		_target = NAN
	throttle.value = setpoint / assist.speed_max


## Radar taps select (the screen leaves taps on a drawer to it).
func _on_radar_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var item: Dictionary = radar.item_at(mb.position)
	if not item.is_empty() and item["kind"] != "point":
		panel.ctx.crew.select(item["kind"], item["id"])
		radar.accept_event()
