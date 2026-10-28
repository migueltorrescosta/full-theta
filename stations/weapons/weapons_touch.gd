class_name WeaponsTouch
extends Control
## Weapons on a phone (#28 follow-up, D287, D289): the turret view with touch controls that
## feed the panel the same intents as the keyboard and the pad (FT-STN-005).
##
## On its side: one overlay rail at the right over a full-width view. The rail holds the
## page zone at the top and FIRE (held: `fire`) at the thumb, which never pages away. Pages
## (PageHost, tabs in the top bar): Fire, the resting page, with the camera mount card (tap:
## `mount_next`), the ammunition (`ammo_next`), Guided (`fire_guided`), Fire all (held:
## `fire_all`) and Claim or Release (the screen's `claim`); Mounts, a list of every mount
## over the view (FT-WPN-004: tap a row to look through it, `mount_N`; its Claim claims it);
## Crew (CrewPage: request chips, Ping, Mark, shares). Over the view's left: the target line
## and the 160 px disc radar inset (FT-WPN-002) at the bottom; the panel draws the feeds
## under the target line.
##
## Upright: the view, then a controls block: the page zone at the left, the mount card and
## FIRE at the right; the tabs sit in the screen's bottom tab bar. A finger dragged across
## the view aims, a tap selects, a long-press pings or marks (WeaponsAimPad).

## The pages.
enum Page { FIRE, MOUNTS, CREW }

## Rail width (px): 152 px of controls inside the rail's padding.
const RAIL_W: float = 168.0
## The radar inset (px): as wide as the rail, so its chips fit beside their blips.
const RADAR_W: float = 168.0
const RADAR_H: float = 124.0
## The mount card shows two lines.
const MOUNT_H: float = 64.0
const FIRE_H: float = 104.0
## Combat numbers (the mount card, the mount list) at 14 px; labels at 13 px.
const FONT_NUM: int = 14
const FONT_LABEL: int = 13
## How far (px) a tap on the radar reaches for a blip.
const RADAR_REACH: float = 24.0
## A mount list row and its Claim button (px).
const ROW_H: float = 56.0
const ROW_CLAIM_W: float = 88.0
## The mount list's widest (px).
const LIST_W: float = 392.0

## The LayoutMode.Form this arrangement is for.
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
## Holds the turret view, its overlay and the aim pad.
var stage: Control = Control.new()
var pad: WeaponsAimPad = WeaponsAimPad.new()
var mount_button: RailButton
var claim_button: RailButton
var ammo_button: RailButton
var guided_button: RailButton
var fire_all_button: RailButton
var fire_button: RailButton
## The target line over the view.
var target_label: Label = Label.new()
## The disc radar inset, or null upright in a joint view (the screen's radar shows there).
var radar: DiscRadar = null
## The radar's backing panel (the radar's place), or null.
var radar_box: PanelContainer = null
## The landscape rail, else null.
var layout: RailLayout = null
## The pages (also the panel's `pages`).
var pages: PageHost = PageHost.new()
## The Fire page's controls.
var fire_zone: VBoxContainer = VBoxContainer.new()
## The Mounts page: a panel over the view with a row per mount (scrolls past the view).
var mount_list: PanelContainer = PanelContainer.new()
## The Crew page.
var crew: CrewPage
## The mount list's rows: [look button, claim button] per mount.
var rows: Array[Array] = []
## Over the view: the target line, the radar, the mount list.
var overlays: Control = Control.new()

var _panel: WeaponsPanel
var _list_box: VBoxContainer = VBoxContainer.new()
var _scroll: ScrollContainer = ScrollContainer.new()


func _init(panel: WeaponsPanel, for_form: LayoutMode.Form, with_radar: bool) -> void:
	_panel = panel
	form = for_form
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.dragged.connect(panel.touch_aim)
	pad.tapped.connect(func(p: Vector2) -> void: panel.touch_select(pad.get_global_transform() * p))
	overlays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_buttons()
	_make_overlays(with_radar)
	crew = CrewPage.new(panel)
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		_landscape()
	else:
		_portrait()
	add_child(overlays)
	pages.add_page(TouchText.of("page.fire", "Fire"), [fire_zone])
	pages.add_page(TouchText.of("page.mounts", "Mounts"), [mount_list])
	pages.add_page(TouchText.of("page.crew", "Crew"), [crew])
	pages.page_changed.connect(func(_i: int) -> void: _panel.queue_redraw())


## Moves the panel's view and overlay onto the stage, under the aim pad.
func take_view(view: Control, overlay: Control) -> void:
	for c: Control in [view, overlay]:
		c.reparent(stage, false)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(pad)


## The view's free part in this arrangement's (the panel's) coordinates: between the left
## edge and the rail on its side; upright the stage less a gap at its top, which keeps the
## view-top row's targets clear of the "turn sideways" banner above it.
func view_rect() -> Rect2:
	if layout != null:
		return layout.content_rect_in(self)
	var gap: Vector2 = Vector2(0.0, UiTheme.TOUCH_GAP)
	return Rect2(stage.position + gap, stage.size - gap)


## The feeds show on the Fire and Crew pages (the mount list covers them on Mounts).
func shows_feeds() -> bool:
	return pages.current != Page.MOUNTS


## Where the panel draws the feed lines (the overlay's coordinates): under the target line
## at the view's left, or beside the radar when `height` px don't fit above it.
func feeds_origin(overlay: Control, height: float) -> Vector2:
	var to_overlay: Transform2D = (
		overlay.get_global_transform().affine_inverse() * get_global_transform()
	)
	var gap: float = UiTheme.TOUCH_GAP
	var x: float = _area().position.x + gap
	var top: float = target_label.position.y + target_label.size.y + gap / 2.0
	if not target_label.visible or target_label.text == "":
		top = _top()
	var floor_y: float = radar_box.position.y - gap if radar_box != null else _area().end.y
	if top + height <= floor_y or radar_box == null:
		return to_overlay * Vector2(x, top)
	return (
		to_overlay * Vector2(radar_box.position.x + radar_box.size.x + gap, _area().end.y - height)
	)


## The top (in the overlay's coordinates) under which read-outs sit: below the view-top row.
func read_top(overlay: Control) -> float:
	var xf: Transform2D = overlay.get_global_transform().affine_inverse() * get_global_transform()
	return (xf * Vector2(0.0, _top())).y


## Texts, states and places from the panel, once a frame.
func refresh() -> void:
	var p: WeaponsPanel = _panel
	mount_button.text = p.mount_text(p.mount)
	claim_button.text = _claim_text(p.mount)
	claim_button.disabled = not p.is_usable(p.mount)
	ammo_button.text = p.ammo_name() + " ▸"
	# (no target line on a phone: the frame's selection chip names the target)
	target_label.text = ""
	if radar != null:
		radar.set_picture(p.ctx.picture(), p.ctx.crew.selection)
	if mount_list.visible:
		_refresh_rows()
	_place()


## The mount list's rows from the panel: "1 bow · ready / heat 15% · 380/400", the camera
## mount accented, and the claim button's Claim, Release or holder.
func _refresh_rows() -> void:
	var p: WeaponsPanel = _panel
	if rows.size() != p.mount_count():
		for r: Array in rows:
			(r[0] as Control).get_parent().queue_free()
		rows.clear()
		for i: int in p.mount_count():
			var look: RailButton = RailButton.make("")
			look.name = "Mount%d" % (i + 1)
			look.custom_minimum_size.y = ROW_H
			look.alignment = HORIZONTAL_ALIGNMENT_LEFT
			look.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			look.clip_text = false
			look.add_theme_font_size_override("font_size", FONT_NUM)
			look.pressed.connect(_look.bind(i))
			var claim: RailButton = RailButton.make("")
			claim.name = "Claim%d" % (i + 1)
			claim.custom_minimum_size = Vector2(ROW_CLAIM_W, ROW_H)
			claim.add_theme_font_size_override("font_size", FONT_LABEL)
			claim.pressed.connect(_claim_row.bind(i))
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
			look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(look)
			row.add_child(claim)
			_list_box.add_child(row)
			rows.append([look, claim])
	for i: int in rows.size():
		var look: RailButton = rows[i][0]
		var claim: RailButton = rows[i][1]
		look.text = p.mount_text(i)
		look.role = RailButton.Role.ACCENT if i == p.mount else RailButton.Role.PLAIN
		look.disabled = not p.is_usable(i)
		claim.text = _claim_text(i)
		claim.disabled = not p.is_usable(i)


func _claim_text(i: int) -> String:
	if _panel.is_mine(i):
		return TouchText.of("weapons.touch_release", "Release")
	if _panel.is_usable(i):
		return TouchText.of("weapons.touch_claim", "Claim")
	return _panel.holder_name(i)


## Look through mount i (its key's intent: 1-4).
func _look(i: int) -> void:
	if i < 4:
		_panel.touch_press("mount_%d" % (i + 1))
	else:
		_panel.select_mount(i)


## Claim (or release) mount i from its row: look through it, then the screen's `claim`.
func _claim_row(i: int) -> void:
	_look(i)
	if _panel.mount == i:
		_panel.touch_claim()


func _make_buttons() -> void:
	mount_button = RailButton.make("", RailButton.Role.ACCENT)
	mount_button.name = "MountCard"
	mount_button.custom_minimum_size.y = MOUNT_H
	mount_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mount_button.clip_text = false
	mount_button.add_theme_font_size_override("font_size", FONT_NUM)
	mount_button.pressed.connect(_panel.touch_press.bind("mount_next"))
	claim_button = RailButton.make("")
	claim_button.name = "Claim"
	claim_button.pressed.connect(_panel.touch_claim)
	ammo_button = RailButton.make("")
	ammo_button.name = "Ammo"
	ammo_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ammo_button.clip_text = false
	ammo_button.pressed.connect(_panel.touch_press.bind("ammo_next"))
	guided_button = RailButton.make(TouchText.of("weapons.touch_guided", "Guided"))
	guided_button.name = "Guided"
	guided_button.pressed.connect(_panel.touch_press.bind("fire_guided"))
	fire_all_button = RailButton.make(TouchText.of("weapons.touch_fire_all", "Fire all"))
	fire_all_button.name = "FireAll"
	fire_all_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_all_button.clip_text = false
	fire_all_button.hold = true
	fire_all_button.held.connect(_panel.touch_hold.bind("fire_all"))
	for b: RailButton in [claim_button, ammo_button, guided_button, fire_all_button]:
		b.add_theme_font_size_override("font_size", FONT_LABEL)
	fire_button = RailButton.make(
		TouchText.of("weapons.touch_fire", "FIRE"), RailButton.Role.DANGER
	)
	fire_button.name = "Fire"
	fire_button.hold = true
	fire_button.custom_minimum_size.y = FIRE_H
	fire_button.held.connect(_panel.touch_hold.bind("fire"))


## The target line, the radar inset in its panel and the mount list, over the view.
func _make_overlays(with_radar: bool) -> void:
	target_label.name = "Target"
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_label.add_theme_font_size_override("font_size", FONT_NUM)
	target_label.add_theme_color_override("font_color", Palette.color("text"))
	target_label.add_theme_color_override("font_outline_color", Palette.color("background"))
	target_label.add_theme_constant_override("outline_size", 4)
	target_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_label.visible = false
	overlays.add_child(target_label)
	if with_radar:
		radar_box = PanelContainer.new()
		radar_box.name = "RadarInset"
		radar_box.theme_type_variation = "OverlayRail"
		# A finger on the inset is the radar's (select, range), never the screen's fire.
		radar_box.add_to_group(TouchInput.GROUP)
		# The disc fills its panel (the rail's padding would shrink it to fewer chips).
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA)
		bg.set_corner_radius_all(4)
		radar_box.add_theme_stylebox_override("panel", bg)
		radar = DiscRadar.new()
		radar.gui_input.connect(_on_radar_input)
		radar_box.add_child(radar)
		overlays.add_child(radar_box)
	mount_list.name = "MountList"
	mount_list.theme_type_variation = "OverlayRail"
	_list_box.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_list_box)
	mount_list.add_child(_scroll)
	overlays.add_child(mount_list)


func _landscape() -> void:
	layout = RailLayout.new()
	add_child(layout)
	layout.set_content(stage)
	layout.content_rect_changed.connect(func(_r: Rect2) -> void: _place())
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RAIL_W
	var zone: VBoxContainer = VBoxContainer.new()
	zone.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add(zone)
	_fill_fire_zone(true)
	zone.add_child(fire_zone)
	fire_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone.add_child(crew)
	right.add(fire_button)


## The Fire page: (the mount card on its side), [ammo | Guided], [Fire all | Claim].
func _fill_fire_zone(with_card: bool) -> void:
	fire_zone.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	if with_card:
		fire_zone.add_child(mount_button)
	for pair: Array in [[ammo_button, guided_button], [fire_all_button, claim_button]]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		for b: RailButton in pair:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		fire_zone.add_child(row)


## Upright: the view, then the controls block: the page zone at the left, the mount card
## and FIRE at the right (under the right thumb).
func _portrait() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(col)
	col.add_child(stage)
	var bar: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		bar.add_theme_constant_override(side, UiTheme.TOUCH_GAP)
	bar.add_to_group(TouchInput.GROUP)
	col.add_child(bar)
	var block: HBoxContainer = HBoxContainer.new()
	block.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	block.custom_minimum_size.y = MOUNT_H + UiTheme.TOUCH_GAP + FIRE_H
	bar.add_child(block)
	var zone: VBoxContainer = VBoxContainer.new()
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(zone)
	_fill_fire_zone(false)
	zone.add_child(fire_zone)
	zone.add_child(crew)
	var thumb: VBoxContainer = VBoxContainer.new()
	thumb.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(thumb)
	thumb.add_child(mount_button)
	fire_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.add_child(fire_button)


## Where taps may go over the view (this control's coordinates): the safe part of the view.
func _area() -> Rect2:
	if layout != null:
		var r: Rect2 = layout.tap_area()
		var v: Rect2 = view_rect()
		return Rect2(r.position.x, r.position.y, v.end.x - r.position.x, r.size.y)
	return Rect2(stage.position, stage.size)


## The top of the read-outs: under the view-top row (the panel's top_reserve).
func _top() -> float:
	return view_rect().position.y + _panel.top_reserve + UiTheme.TOUCH_GAP


## Places the overlays: the target line at the top left, the radar at the bottom left, the
## mount list (Mounts page) beside the radar's column where the view is wide enough, else
## above the radar.
func _place() -> void:
	var area: Rect2 = _area()
	var gap: float = UiTheme.TOUCH_GAP
	var x: float = area.position.x + gap
	var top: float = _top()
	# As wide as its text, wrapping past half the view (at least the radar's width).
	var w: float = maxf(RADAR_W, minf(area.size.x / 2.0, 260.0))
	var font: Font = target_label.get_theme_font("font")
	var text_w: float = (
		font.get_string_size(target_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_NUM).x
	)
	w = minf(w, ceilf(text_w) + 2.0)
	target_label.position = Vector2(x, top)
	target_label.size = Vector2(w, 0.0)
	target_label.size = Vector2(w, target_label.get_combined_minimum_size().y)
	var list: Rect2 = Rect2(x, top, area.end.x - gap - x, area.end.y - gap - top)
	if radar_box != null:
		var r: Rect2 = Rect2(x, area.end.y - gap - RADAR_H, RADAR_W, RADAR_H)
		if radar_box.position != r.position or radar_box.size != r.size:
			radar_box.position = r.position
			radar_box.size = r.size
		if area.end.x - gap - (r.end.x + gap) >= LIST_W * 0.75:
			list.position.x = r.end.x + gap
			list.size.x = area.end.x - gap - list.position.x
		else:
			list.size.y = r.position.y - gap - top
	var need: float = maxf(ROW_H, rows.size() * (ROW_H + gap) - gap) + 2.0 * gap
	mount_list.position = list.position
	mount_list.size = Vector2(minf(LIST_W, list.size.x), minf(list.size.y, need))


## A finger on the radar inset selects the nearest blip (the screen never sees taps on it);
## the range label still steps the range through the emulated mouse.
func _on_radar_input(event: InputEvent) -> void:
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t == null or t.pressed:
		return
	var item: Dictionary = radar.item_at(t.position, RADAR_REACH)
	if not item.is_empty() and item["kind"] != "point":
		_panel.ctx.crew.select(item["kind"], item["id"])
