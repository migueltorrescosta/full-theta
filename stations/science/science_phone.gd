class_name SciencePhone
extends Control
## Science on a phone (#28, owner pick 2026-10-28: overlay rails, A). Landscape: the radar
## fills the panel under two translucent thumb rails, the contact list and card on the
## left, all eight actions on the right; in a scan the axis chips go left and Cancel and
## Submit right, in a hack the hint goes left and Cancel right, and the minigame sits
## between the rails. Upright (the reduced layout under the screen's "turn sideways"
## banner): the radar or minigame on top, the list and card below it, then the actions
## in rows. The parts (list, card, the stage with the radar and minigames) are the
## panel's own, moved in by `build` and back by `release`; the buttons call the panel's
## commands, so a tap does what the key, the controller and the desktop button do.

const LEFT_W: float = 176.0
const RIGHT_W: float = 168.0
## Upright: the list and card row, and the least height of the radar or minigame.
const PARTS_H: float = 170.0
const STAGE_MIN_H: float = 200.0
## An ItemList row's extra height, so a row is a TOUCH_MIN tap.
const ROW_SEPARATION: int = 25
## The radar's range label is a TOUCH_PRIMARY tap.
const RANGE_MIN: float = 48.0

var panel: SciencePanel
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
## The landscape rails (null upright).
var layout: RailLayout
## Action buttons by the panel's action key ("scan", "hack", ...).
var actions: Dictionary[String, RailButton] = {}
var axis_buttons: Array[RailButton] = []
var submit: RailButton
var cancel: RailButton
## The status line over the bottom of the radar.
var status: Label

## Under the contacts in the left rail: the screen's Share opener (landscape, no minigame).
var share_slot: VBoxContainer = null
var _info: Control
var _action_box: Control
var _scan_left: Control
var _hack_hint: Label
var _game_right: Control
var _card_scroll: ScrollContainer


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


## Moves the panel's parts in and builds the buttons for `phone_form`.
func build(p: SciencePanel, phone_form: LayoutMode.Form) -> void:
	panel = p
	form = phone_form
	_make_controls()
	var list: ItemList = panel._list
	list.add_theme_constant_override("v_separation", ROW_SEPARATION)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.card_view.custom_minimum_size = Vector2(0.0, ScienceCard.content_height())
	panel.card_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.radar.touch_min = RANGE_MIN
	panel.scan_game.footer = false
	panel.hack_game.footer = false
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		_build_landscape()
	else:
		_build_portrait()
	panel.card_view.reparent(_card_scroll, false)
	panel._stage.add_child(status)


## Puts the panel's parts back where the wide layout keeps them.
func release() -> void:
	if panel._stage.resized.is_connected(_on_stage_resized):
		panel._stage.resized.disconnect(_on_stage_resized)
	if layout != null:
		layout.content_rect_changed.disconnect(_place_view)
	var top: BoxContainer = panel._top
	panel._list.remove_theme_constant_override("v_separation")
	panel._list.reparent(top, false)
	top.move_child(panel._list, 0)
	panel._stage.reparent(top, false)
	top.move_child(panel._stage, 1)
	panel._stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel._stage.custom_minimum_size = Vector2.ZERO
	panel._stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel._stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.card_view.reparent(top, false)
	top.move_child(panel.card_view, 2)
	panel.card_view.size_flags_horizontal = 0
	status.queue_free()
	panel.radar.view_rect = Rect2()
	panel.radar.touch_min = 0.0
	# The screen's Share opener isn't ours to free: the screen puts it back.
	if share_slot != null:
		for c: Node in share_slot.get_children():
			share_slot.remove_child(c)
	for g: Control in [panel.scan_game, panel.hack_game]:
		g.footer = true
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_controls() -> void:
	for spec: Array in panel.actions():
		var b: RailButton = RailButton.make(
			"", RailButton.Role.ACCENT if spec[0] == "scan" else RailButton.Role.PLAIN
		)
		b.name = "Phone_" + String(spec[0])
		b.pressed.connect(spec[2])
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
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Overlay rails over the full-size radar (mockup A).
func _build_landscape() -> void:
	layout = RailLayout.new()
	add_child(layout)
	layout.set_content(panel._stage)
	var left: TouchRail = layout.rail(SIDE_LEFT)
	left.custom_minimum_size.x = LEFT_W
	var info: VBoxContainer = _column()
	panel._list.custom_minimum_size = Vector2(0.0, 156.0)
	panel._list.reparent(info, false)
	info.add_child(_card_scroll)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info = left.add(info)
	var axes: VBoxContainer = _column()
	for a: RailButton in axis_buttons:
		axes.add_child(a)
	_scan_left = left.add(axes)
	left.add(_hack_hint)
	share_slot = left.add(_column()) as VBoxContainer
	share_slot.name = "ShareSlot"
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RIGHT_W
	var acts: VBoxContainer = _column()
	for row: Array in [["scan", "hack"], ["sub", "ping"], ["mark", "mode"], ["self"], ["claim"]]:
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


## Upright: the stage, the list and card, then the actions (or the minigame's buttons).
func _build_portrait() -> void:
	var col: VBoxContainer = _column()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	panel._stage.reparent(col, false)
	panel._stage.custom_minimum_size.y = STAGE_MIN_H
	panel._stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var parts: HBoxContainer = HBoxContainer.new()
	parts.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	parts.custom_minimum_size.y = PARTS_H
	panel._list.custom_minimum_size = Vector2.ZERO
	panel._list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel._list.reparent(parts, false)
	parts.add_child(_card_scroll)
	col.add_child(parts)
	_info = parts
	var acts: VBoxContainer = _column()
	for row: Array in [["scan", "hack", "sub"], ["ping", "mark", "self"], ["mode", "claim"]]:
		acts.add_child(_row(row.map(func(k: String) -> RailButton: return actions[k])))
	col.add_child(acts)
	_action_box = acts
	_scan_left = _row(axis_buttons)
	col.add_child(_scan_left)
	col.add_child(_hack_hint)
	_game_right = _row([cancel, submit])
	col.add_child(_game_right)
	panel._stage.resized.connect(_on_stage_resized)


func _on_stage_resized() -> void:
	_place_view(Rect2(Vector2.ZERO, panel._stage.size))


## The radar, the minigames and the status keep to the uncovered part of the stage.
func _place_view(rect: Rect2) -> void:
	var r: Rect2 = rect
	if layout != null:
		r = layout.content_rect_in(panel._stage)
		panel.radar.view_rect = r
	for g: Control in [panel.scan_game, panel.hack_game]:
		g.set_anchors_preset(Control.PRESET_TOP_LEFT)
		g.position = r.position
		g.size = r.size
	var x: float = r.position.x + 6.0 + RANGE_MIN + UiTheme.TOUCH_GAP
	status.position = Vector2(x, r.end.y - 52.0)
	status.size = Vector2(maxf(r.end.x - x - 8.0, 1.0), 46.0)


## Mirrors the panel's state each frame: texts, enabled states and what shows in a session.
func update(session: int) -> void:
	for k: String in actions:
		var src: Button = panel._buttons[k]
		actions[k].text = _short(k, src.text)
		actions[k].disabled = src.disabled
	var playing: bool = session != SciencePanel.SESSION_NONE
	var scan: bool = session == SciencePanel.SESSION_SCAN
	_info.visible = not playing
	if share_slot != null:
		var shown: Array = share_slot.get_children().filter(
			func(c: Node) -> bool: return (c as Control).visible
		)
		share_slot.visible = not playing and not shown.is_empty()
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
			if form == LayoutMode.Form.PHONE_LANDSCAPE:
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
