class_name SciencePhone
extends Control
## Science on a phone (#28 follow-up, design 2.4, owner picks P28-Tabs, P28-Common, P28-L1;
## D287-D289). Landscape: the radar fills the panel under two translucent rails. The right
## rail is the persistent zone: Scan / Hack, Ping / Mark, Passive / Own ship and Take the
## scan. The left rail is the page zone: Contacts (the list), Card (the whole card, wider,
## no scroll; the radar re-centres beside it) and Crew (CrewPage). Hack opens the screen's
## choice sheet of the target's subsystems (SciencePanel.open_hack). While a scan or hack
## runs the tabs show the session's title and the rails swap to the minigame's: the axis
## chips or the hint on the left, Cancel (and Submit) on the right.
## Upright (the reduced layout under the "turn sideways" banner): the radar or minigame on
## top, the page zone under it, then the actions; the screen's bottom tab bar holds the tabs.
## The parts (list, card, the stage with the radar and minigames) are the panel's own,
## moved in by `build` and back by `release`; the buttons call the panel's commands, so a
## tap does what the key, the controller and the desktop button do.

const LEFT_W: float = 168.0
const RIGHT_W: float = 168.0
## The left rail on the Card page (design 2.4: 300 px).
const CARD_W: float = 300.0
## Upright: the least height of the radar or minigame, and the page zone's height (the Card
## page's is the whole card's).
const STAGE_MIN_H: float = 160.0
const ZONE_UP_H: float = 3.0 * (UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP)
## The action buttons' font: "Own ship" fits a half-width rail button.
const ACTION_FONT: int = 14
## An ItemList row's extra height, so a row is a TOUCH_MIN tap.
const ROW_SEPARATION: int = 25
## The radar's range label is a TOUCH_PRIMARY tap.
const RANGE_MIN: float = 48.0
## The persistent actions in rows: landscape (right rail) and upright.
const ROWS_SIDE: Array = [["scan", "hack"], ["ping", "mark"], ["mode", "self"], ["claim"]]
const ROWS_UP: Array = [["scan", "hack", "ping", "mark"], ["mode", "self", "claim"]]
const PAGE_CONTACTS: int = 0
const PAGE_CARD: int = 1
const PAGE_CREW: int = 2

var panel: SciencePanel
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
## The landscape rails (null upright).
var layout: RailLayout
## Contacts, Card, Crew (set on the panel as its `pages`).
var pages: PageHost = PageHost.new()
var crew: CrewPage
## Action buttons by the panel's action key ("scan", "hack", ...; no "sub": the Hack sheet
## picks the subsystem).
var actions: Dictionary[String, RailButton] = {}
var axis_buttons: Array[RailButton] = []
var submit: RailButton
var cancel: RailButton
## The status line over the bottom of the radar.
var status: Label

## The page zone (the list, the card, the Crew page), hidden during a session.
var _zone: Control
var _action_box: Control
var _scan_left: Control
var _hack_hint: Label
var _game_right: Control
var _reserve: float = -1.0
## Upright without the stage (a joint view keeps the screen's radar): room for the
## screen's view-top row above the page zone.
var _top_pad: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A gap under the top bar, so its buttons and the first rail button are apart.
	offset_top = UiTheme.TOUCH_GAP
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The form of the station screen `panel` is on, from the screen's own size: in the game
## it fills the window (LayoutMode.form_of); tests lay a screen out at a set size inside
## the tiny headless window, which alone would read as a phone.
static func form_of_panel(panel: Control) -> LayoutMode.Form:
	var n: Node = panel
	while n != null and not n is StationScreen:
		n = n.get_parent()
	if n == null:
		return LayoutMode.form_of(panel)
	var vp: Viewport = panel.get_viewport()
	var factor: float = (vp as Window).content_scale_factor if vp is Window else 1.0
	var dp: Vector2 = LayoutMode.dp_size((n as Control).size, factor, LayoutMode.density())
	return LayoutMode.form_for(dp, LayoutMode.coarse_pointer())


## Moves the panel's parts in and builds the buttons and pages for `phone_form`.
func build(p: SciencePanel, phone_form: LayoutMode.Form) -> void:
	panel = p
	form = phone_form
	_make_controls()
	panel._list.add_theme_constant_override("v_separation", ROW_SEPARATION)
	panel._list.custom_minimum_size = Vector2.ZERO
	panel._list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.card_view.compact = true
	panel.card_view.custom_minimum_size = Vector2(0.0, ScienceCard.content_height(true))
	panel.card_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.card_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.radar.touch_min = RANGE_MIN
	panel.scan_game.footer = false
	panel.hack_game.footer = false
	crew = CrewPage.new(panel)
	crew.name = "CrewPage"
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		_build_landscape()
	else:
		_build_portrait()
	pages.add_page(TouchText.of("page.contacts", "Contacts"), [panel._list])
	pages.add_page(TouchText.of("page.card", "Card"), [panel.card_view])
	pages.add_page(TouchText.of("page.crew", "Crew"), [crew])
	pages.page_changed.connect(_on_page)
	panel._stage.add_child(status)


## Puts the panel's parts back where the wide layout keeps them.
func release() -> void:
	if panel._stage.resized.is_connected(_on_stage_resized):
		panel._stage.resized.disconnect(_on_stage_resized)
	if layout != null:
		layout.content_rect_changed.disconnect(_place_view)
	pages.session_title = ""
	var top: BoxContainer = panel._top
	panel._list.remove_theme_constant_override("v_separation")
	panel._list.size_flags_vertical = Control.SIZE_FILL
	panel._list.visible = true
	panel._list.reparent(top, false)
	top.move_child(panel._list, 0)
	panel._stage.reparent(top, false)
	top.move_child(panel._stage, 1)
	panel._stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel._stage.custom_minimum_size = Vector2.ZERO
	panel._stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel._stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.card_view.compact = false
	panel.card_view.visible = true
	panel.card_view.size_flags_vertical = Control.SIZE_FILL
	panel.card_view.reparent(top, false)
	top.move_child(panel.card_view, 2)
	panel.card_view.size_flags_horizontal = 0
	status.queue_free()
	panel.radar.view_rect = Rect2()
	panel.radar.touch_min = 0.0
	for g: Control in [panel.scan_game, panel.hack_game]:
		g.footer = true
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_controls() -> void:
	for spec: Array in panel.actions():
		if spec[0] == "sub":
			continue
		var b: RailButton = RailButton.make(
			"", RailButton.Role.ACCENT if spec[0] == "scan" else RailButton.Role.PLAIN
		)
		b.name = "Phone_" + String(spec[0])
		b.add_theme_font_size_override("font_size", ACTION_FONT)
		b.pressed.connect(panel.open_hack if spec[0] == "hack" else spec[2])
		actions[spec[0]] = b
	for i: int in 3:
		var a: RailButton = RailButton.make("")
		a.name = "Axis%d" % i
		a.pressed.connect(panel.scan_game.select_axis.bind(i))
		axis_buttons.append(a)
	submit = RailButton.make(tr("sci.submit"), RailButton.Role.ACCENT)
	submit.name = "Submit"
	submit.pressed.connect(panel.scan_game.submit)
	cancel = RailButton.make(tr("sci.cancel"))
	cancel.name = "Cancel"
	cancel.pressed.connect(panel.cancel_session)
	_hack_hint = Label.new()
	_hack_hint.text = TouchText.of("sci.hack_tap", "Tap a node next to the green one.")
	_hack_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hack_hint.add_theme_color_override("font_color", Palette.color("text_dim"))
	status = Label.new()
	status.name = "PhoneStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	status.max_lines_visible = 2
	status.add_theme_color_override("font_color", Palette.color("text_dim"))
	status.add_theme_font_size_override("font_size", 13)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Overlay rails over the full-size radar: the page zone left, the actions right.
func _build_landscape() -> void:
	layout = RailLayout.new()
	add_child(layout)
	layout.set_content(panel._stage)
	var left: TouchRail = layout.rail(SIDE_LEFT)
	left.custom_minimum_size.x = LEFT_W
	var zone: VBoxContainer = _column()
	zone.name = "PageZone"
	zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel._list.reparent(zone, false)
	panel.card_view.reparent(zone, false)
	zone.add_child(crew)
	_zone = left.add(zone)
	var axes: VBoxContainer = _column()
	for a: RailButton in axis_buttons:
		axes.add_child(a)
	_scan_left = left.add(axes)
	left.add(_hack_hint)
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RIGHT_W
	var acts: VBoxContainer = _column()
	for row: Array in ROWS_SIDE:
		acts.add_child(_row(row.map(func(k: String) -> RailButton: return actions[k])))
	_action_box = right.add(acts)
	var game: VBoxContainer = _column()
	game.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var push: Control = Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(push)
	game.add_child(cancel)
	submit.custom_minimum_size.y = 104.0
	game.add_child(submit)
	_game_right = right.add(game)
	layout.content_rect_changed.connect(_place_view)


## Upright: the stage, the page zone, then the actions (or the minigame's buttons).
func _build_portrait() -> void:
	var col: VBoxContainer = _column()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	_top_pad = Control.new()
	_top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_top_pad)
	panel._stage.reparent(col, false)
	panel._stage.custom_minimum_size.y = STAGE_MIN_H
	panel._stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var zone: VBoxContainer = _column()
	zone.name = "PageZone"
	zone.custom_minimum_size.y = ZONE_UP_H
	panel._list.reparent(zone, false)
	panel.card_view.reparent(zone, false)
	zone.add_child(crew)
	col.add_child(zone)
	_zone = zone
	var acts: VBoxContainer = _column()
	for row: Array in ROWS_UP:
		acts.add_child(_row(row.map(func(k: String) -> RailButton: return actions[k])))
	col.add_child(acts)
	_action_box = acts
	_scan_left = _row(axis_buttons)
	col.add_child(_scan_left)
	col.add_child(_hack_hint)
	_game_right = _row([cancel, submit])
	col.add_child(_game_right)
	panel._stage.resized.connect(_on_stage_resized)


## The Card page widens the left rail (upright: the page zone) so the whole card shows; the
## radar re-centres.
func _on_page(index: int) -> void:
	var card: bool = index == PAGE_CARD
	if layout == null:
		_zone.custom_minimum_size.y = ScienceCard.content_height(true) if card else ZONE_UP_H
		return
	layout.left.custom_minimum_size.x = CARD_W if card else LEFT_W
	layout.queue_sort()


func _on_stage_resized() -> void:
	_place_view(Rect2(Vector2.ZERO, panel._stage.size))


## The stage's part the radar draws in, in the stage's coordinates: between the rails,
## under the screen's view-top row (StationPanel.top_reserve), and above the gesture band
## (the range label is a tap).
func view_in_stage() -> Rect2:
	var r: Rect2 = Rect2(Vector2.ZERO, panel._stage.size)
	if layout != null:
		r = layout.content_rect_in(panel._stage)
		var tap: Rect2 = layout.tap_area()
		var bottom: float = (
			(
				panel._stage.get_global_transform().affine_inverse()
				* (layout.get_global_transform() * tap.end)
			)
			. y
		)
		r.size.y = minf(r.size.y, bottom - r.position.y)
	var top: float = panel.top_reserve
	r.position.y += top
	r.size.y = maxf(r.size.y - top - panel.bottom_reserve, 1.0)
	return r


## The radar, the minigames and the status keep to the uncovered part of the stage.
func _place_view(_rect: Rect2 = Rect2()) -> void:
	_reserve = panel.top_reserve
	var r: Rect2 = view_in_stage()
	# Before the first layout the free part can be a sliver: draw over the whole stage.
	if r.size.x < 2.0 * RANGE_MIN or r.size.y < 2.0 * RANGE_MIN:
		r = Rect2(Vector2.ZERO, panel._stage.size)
	panel.radar.view_rect = r
	for g: Control in [panel.scan_game, panel.hack_game]:
		g.set_anchors_preset(Control.PRESET_TOP_LEFT)
		g.position = r.position
		g.size = r.size
	# The status reads beside the range label, down into the gesture band on its side
	# (P28-Band: drawn into, never tapped), clear of the disc's foot.
	var x: float = r.position.x + 6.0 + RANGE_MIN + UiTheme.TOUCH_GAP
	var foot: float = panel._stage.size.y - 2.0 if layout != null else r.end.y
	status.position = Vector2(x, foot - 40.0)
	status.size = Vector2(maxf(r.end.x - x - 8.0, 1.0), 40.0)


## Mirrors the panel's state each frame: texts, enabled states, the session's title and
## what shows in a session.
func update(session: int) -> void:
	if panel.top_reserve != _reserve:
		_place_view()
	if _top_pad != null:
		var pad: float = 0.0 if panel._stage.visible else panel.top_reserve
		if _top_pad.custom_minimum_size.y != pad:
			_top_pad.custom_minimum_size.y = pad
	for k: String in actions:
		var src: Button = panel._buttons[k]
		actions[k].text = _short(k, src.text)
		actions[k].disabled = src.disabled
	actions["hack"].disabled = not panel.can_open_hack()
	var playing: bool = session != SciencePanel.SESSION_NONE
	var scan: bool = session == SciencePanel.SESSION_SCAN
	pages.session_title = panel.session_title() if playing else ""
	_zone.visible = not playing
	_action_box.visible = not playing
	_scan_left.visible = scan
	_hack_hint.visible = session == SciencePanel.SESSION_HACK
	_game_right.visible = playing
	submit.visible = scan
	status.text = panel._status.text
	status.visible = not playing
	if scan:
		var open: Array[int] = panel.scan_game.open_axes()
		for i: int in axis_buttons.size():
			var a: RailButton = axis_buttons[i]
			a.visible = i < open.size()
			if a.visible:
				var deg: int = roundi(rad_to_deg(panel.scan_game.angles[open[i]]))
				a.text = "%s %d°" % ["XYZ"[open[i]], deg]
				a.role = (
					RailButton.Role.ACCENT
					if i == panel.scan_game.selected
					else RailButton.Role.PLAIN
				)


## Shorter labels where a phone's half-width button has no room for the desktop's.
func _short(key: String, text: String) -> String:
	match key:
		"mark":
			return TouchText.of("sci.short_mark", "Mark")
		"self":
			return TouchText.of("sci.short_self", "Own ship")
		"mode":
			var active: bool = bool(panel.block().get("active", false))
			if active:
				return TouchText.of("sci.short_active", "Active")
			return TouchText.of("sci.short_passive", "Passive")
	return text


func _column() -> VBoxContainer:
	var c: VBoxContainer = VBoxContainer.new()
	c.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	return c


func _row(controls: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
	return row
