class_name HelmTouch
extends Control
## Helm's phone layouts (#28, FT §5.1 touch, D195, owner picks P28-Rails, P28-Shield,
## P28-Chase): the touch controls over the cockpit, in the shared phone frame's pages.
## Touch changes the arrangement only: every control fires the Helm intent its key or
## button fires (TouchIntents), so the panel's commands are the same.
##
## Landscape: two overlay rails over the full view. The persistent zone never pages away:
## on the left the throttle, All stop, Approach and the Turn stick (attitude), on the right
## the Slide stick (translation). The right rail's top holds the page zone (PageHost):
##   Fly (rest): Face (hold), Align, Track.
##   Shield: the shield ring filling the page zone (tap a cell: FT-HLM-009; its caption
##     gives power, focus tightness and tracking: FT-HLM-011).
##   Nav: Dock, Jump, Chase, Decoupled.
##   Radar: the disc radar over the view, the HUD hidden (a tap selects); Range −, Range +.
##   Crew: the screen's CrewPage (Boost request, Ping, Mark, Shares).
## Under the buttons of Fly, Nav and Radar the ring shows as a glyph that takes no taps, so
## the view keeps nothing but the HUD.
##
## Portrait (owner pick A, plus the bottom tab bar): the view on top and one block of
## controls below it: throttle, Turn / Slide (what the one stick does), All stop, Approach,
## the stick, and the page zone as a two-column grid; the screen's banner asks to turn
## sideways.
##
## The throttle sets the speed setpoint, as the spec's assist-only touch throttle: while the
## slider differs from the HELM block's setpoint, it feeds helm_surge (the S/W and trigger
## axis) until the setpoint gets there, then shows the setpoint again (All stop, Approach,
## the keyboard).

## Rail widths (design 2.1: 168 px rails) and the portrait block's height (the mockups).
const LEFT_W: float = 168.0
const RIGHT_W: float = 168.0
const BLOCK_H: float = 300.0
## The least a button's text shrinks to so it fits (fit_text).
const MIN_FONT: int = 12
## The throttle stops feeding helm_surge within this many m/s of its setpoint; the input is
## the gap over GAIN_S seconds of full ramp.
const SETPOINT_TOLERANCE: float = 1.0
const GAIN_S: float = 0.5
## The controls' English texts until content/i18n/strings.json has their "touch.helm.*" keys.
const TEXTS: Dictionary = {
	"all_stop": "All stop",
	"approach": "Approach",
	"turn": "Turn",
	"slide": "Slide",
	"fly": "Fly",
	"shield": "Shield",
	"nav": "Nav",
	"radar_title": "Radar",
	"face": "Face",
	"align": "Align",
	"dock": "Dock",
	"jump": "Jump",
	"chase_camera": "Chase",
	"decoupled": "Decoupled",
	"shield_track": "Track",
	"range_in": "Range −",
	"range_out": "Range +",
}
## The portrait banner's text (StationScreen.rotate_banner).
const ROTATE_KEY: String = "touch.rotate_helm"
const ROTATE_TEXT: String = "Turn sideways for the full Helm"
## The pages, in tab order (the first is the resting state).
const PAGE_FLY: int = 0
const PAGE_SHIELD: int = 1
const PAGE_NAV: int = 2
const PAGE_RADAR: int = 3
const PAGE_CREW: int = 4
## Each page's Helm buttons (intent ids; "range_in" and "range_out" step the radar).
const PAGE_IDS: Array = [
	["face", "align", "shield_track"],
	[],
	["dock", "jump", "chase_camera", "decoupled"],
	["range_in", "range_out"],
	[],
]
## Buttons lit while their mode is on.
const TOGGLES: Array = ["shield_track", "chase_camera", "decoupled"]

var panel: HelmPanel
var portrait: bool = false
var touch: TouchIntents
## The first button of each Helm intent: id -> RailButton (All stop, Approach and each
## page's buttons).
var buttons: Dictionary = {}
## Each page's buttons: page_buttons[page][id] -> RailButton.
var page_buttons: Array[Dictionary] = []
var throttle: ThrottleSlider
## Landscape: the two sticks; portrait: `turn` is the one stick and `slide` is null.
var turn: VirtualStick
var slide: VirtualStick
## Portrait: what the one stick drives.
var stick_slides: bool = false
var mode_turn: RailButton
var mode_slide: RailButton
## The pages (the screen draws the tabs; HelmPanel sets them as its `pages`).
var pages: PageHost = PageHost.new()
var crew: CrewPage
var radar: DiscRadar
## The Radar page's panel behind the radar (the overlay alpha, UiTheme.OVERLAY_ALPHA).
var radar_box: PanelContainer
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
	radar.name = "Radar"
	radar.gui_input.connect(_on_radar_input)
	radar_box = PanelContainer.new()
	radar_box.name = "RadarBox"
	radar_box.theme_type_variation = "OverlayRail"
	# A finger on the radar selects there (the screen leaves it alone).
	radar_box.add_to_group(TouchInput.GROUP)
	radar_box.add_child(radar)
	add_child(radar_box)
	crew = CrewPage.new(panel)
	if portrait:
		_build_portrait()
	else:
		_build_landscape()
	pages.page_changed.connect(func(_i: int) -> void: panel.hud.queue_redraw())


## A rail button for a Helm intent (or a radar step), wired to it.
func _button(id: String, role: RailButton.Role = RailButton.Role.PLAIN) -> RailButton:
	var b: RailButton = RailButton.make(text(id), role)
	b.name = id
	match id:
		"range_in":
			b.pressed.connect(func() -> void: radar.zoom(-1))
		"range_out":
			b.pressed.connect(func() -> void: radar.zoom(1))
		_:
			touch.button(b, id)
	if not buttons.has(id):
		buttons[id] = b
	b.resized.connect(fit_text.bind(b))
	return b


## Shrinks `b`'s text, down to MIN_FONT, until it fits the button (a long word in a half
## rail button, a longer language).
static func fit_text(b: Button) -> void:
	b.remove_theme_font_size_override("font_size")
	var font: Font = b.get_theme_font("font")
	var room: float = b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x
	var fs: int = b.get_theme_font_size("font_size")
	while (
		fs > MIN_FONT and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room
	):
		fs -= 1
	b.add_theme_font_size_override("font_size", fs)


## The page titles, in PAGE_* order.
static func page_titles() -> Array[String]:
	return [
		text("fly"),
		text("shield"),
		text("nav"),
		text("radar_title"),
		TouchText.of("page.crew", "Crew"),
	]


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
	turn = _stick("turn")
	touch.stick(turn, "helm_yaw", "helm_pitch")
	turn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(turn)
	var row: HBoxContainer = left.add_row([throttle, col])
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	throttle.size_flags_horizontal = Control.SIZE_FILL
	col.size_flags_stretch_ratio = 2.0
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RIGHT_W
	_fill_pages(right.box)
	slide = _stick("slide")
	# Right stick: x strafes to starboard, up lifts (the pad's RS_X and -RS_Y).
	touch.stick(slide, "helm_sway", "helm_heave", 1.0, -1.0)
	right.add(slide)
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
		b.resized.connect(fit_text.bind(b))
		modes.add_child(b)
	mode_turn.name = "mode_turn"
	mode_slide.name = "mode_slide"
	mode_turn.button_pressed = true
	mode_turn.pressed.connect(set_stick_slides.bind(false))
	mode_slide.pressed.connect(set_stick_slides.bind(true))
	col.add_child(_button("all_stop", RailButton.Role.DANGER))
	col.add_child(_button("approach"))
	turn = _stick("turn")
	turn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	turn.moved.connect(_on_one_stick)
	turn.name = "stick"
	col.add_child(turn)
	var zone: VBoxContainer = VBoxContainer.new()
	zone.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone.size_flags_stretch_ratio = 2.0
	row.add_child(zone)
	_fill_pages(zone)


## The page zone in `box`: each page's buttons, the Crew page, and the shield ring under
## them (the whole zone on the Shield page, a glyph on Fly, Nav and Radar; it fills what
## the buttons leave).
func _fill_pages(box: VBoxContainer) -> void:
	var titles: Array[String] = page_titles()
	var parts: Array[Array] = []
	for p: int in titles.size():
		parts.append([])
		if not (PAGE_IDS[p] as Array).is_empty():
			var grid: GridContainer = _grid(PAGE_IDS[p], 2, p)
			box.add_child(grid)
			parts[p].append(grid)
	crew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(crew)
	parts[PAGE_CREW].append(crew)
	var ring: ShieldRing = panel.ring
	ring.reparent(box, false)
	ring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for p: int in [PAGE_FLY, PAGE_SHIELD, PAGE_NAV, PAGE_RADAR]:
		parts[p].append(ring)
	parts[PAGE_RADAR].append(radar_box)
	for p: int in titles.size():
		pages.add_page(titles[p], parts[p])


## A grid of `columns` rail buttons for Helm intents on page `page`.
func _grid(ids: Array, columns: int, page: int) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.name = "Page%d" % page
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	while page_buttons.size() <= page:
		page_buttons.append({})
	for id: String in ids:
		var b: RailButton = _button(id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		page_buttons[page][id] = b
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


## The view clear of the controls, the banner and the screen's view-top row (the panel's
## view_rect less top_reserve), in `control`'s coordinates: where the HUD and the radar go.
func clear_view_in(control: Control) -> Rect2:
	var r: Rect2 = panel.view_rect()
	var top: float = minf(panel.top_reserve, r.size.y)
	r.position.y += top
	r.size.y -= top
	var xf: Transform2D = (
		control.get_global_transform().affine_inverse() * panel.get_global_transform()
	)
	return xf * r


## The view's height above the portrait block (the 3D view and the HUD stop there).
func view_bottom_inset() -> float:
	return BLOCK_H if portrait else 0.0


## Every frame: the throttle, the ring, the radar and the lit mode buttons.
func update(ring: ShieldRing) -> void:
	_drive_throttle()
	_place_radar()
	if radar_box.is_visible_in_tree():
		radar.set_picture(panel.ctx.picture(), panel.ctx.crew.selection)
	_place_ring(ring)
	var h: Dictionary = panel.helm_block()
	var on: Dictionary = {
		"shield_track": int(h.get("shield_track", -1)) >= 0,
		"chase_camera": panel.chase,
		"decoupled": bool(h.get("decoupled", false)),
	}
	for page: Dictionary in page_buttons:
		for id: String in TOGGLES:
			if page.has(id):
				var b: RailButton = page[id]
				var role: RailButton.Role = (
					RailButton.Role.ACCENT if on[id] else RailButton.Role.PLAIN
				)
				if b.role != role:
					b.role = role


## The Radar page: the radar's panel over the whole clear view above the bottom band (its
## range label is a tap target); the HUD hides under it.
func _place_radar() -> void:
	var free: Rect2 = clear_view_in(self)
	if layout != null:
		var rail: Rect2 = layout.right.get_global_rect()
		free.size.y = minf(free.size.y, rail.end.y - get_global_rect().position.y - free.position.y)
	free = free.grow(-UiTheme.TOUCH_GAP)
	radar_box.position = free.position.round()
	radar_box.size = free.size.round()
	panel.hud.visible = not radar_box.visible


## The ring: tappable with its caption on the Shield page, a glyph that takes no taps
## elsewhere. HelmPanel takes it back when the layout goes.
func _place_ring(ring: ShieldRing) -> void:
	var big: bool = pages.current == PAGE_SHIELD
	ring.label = big
	ring.mouse_filter = Control.MOUSE_FILTER_STOP if big else Control.MOUSE_FILTER_IGNORE


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


## Radar taps select (the screen leaves taps on the radar to it).
func _on_radar_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var item: Dictionary = radar.item_at(mb.position)
	if not item.is_empty() and item["kind"] != "point":
		panel.ctx.crew.select(item["kind"], item["id"])
		radar.accept_event()
