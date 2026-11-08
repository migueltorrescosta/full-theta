class_name CommsPhone
extends RefCounted
## Comms on a phone (#28 follow-up, D287, design 2.6): the layout half of CommsPanel. On its
## side the five buttons move to a docked left rail and the board's rows sit beside it;
## upright they stay in the bar under the board, touch-sized on two rows. On a phone either
## way up two spacers keep the rows under the view-top row and above the gesture band, and
## the conversation (CommsOverlay) becomes a top-level control placed over the board.
##
## CommsPanel builds it, adds its spacers to the rows, and keeps the widgets, the intents
## and the page and mode switching; this only moves and sizes the panel's widgets.

var panel: CommsPanel
## The phone-landscape arrangement (#28, docked rails like Weapons B): the five buttons in a
## docked rail at the screen's left edge, the board beside it. Made on first use.
var layout: RailLayout = null
## A phone's spacers: under the view-top row, and above the gesture band.
var top_gap: Control = Control.new()
var foot_gap: Control = Control.new()


func _init(owner_panel: CommsPanel) -> void:
	panel = owner_panel
	for gap: Control in [top_gap, foot_gap]:
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.visible = false


## True when the panel takes the phone-landscape arrangement: focused on a phone on its side.
func landscape() -> bool:
	return (
		panel.is_inside_tree()
		and not panel.docked
		and LayoutMode.form_of(panel) == LayoutMode.Form.PHONE_LANDSCAPE
	)


## True when the panel shows its pages: its main view on a phone, either way up.
func paged() -> bool:
	return (
		panel.is_inside_tree()
		and not panel.docked
		and LayoutMode.is_phone(LayoutMode.form_of(panel))
	)


## A phone's width (under NARROW_BAR px) keeps the five buttons on one row: smaller text and
## gaps, so Hold fire doesn't drop to a row of its own.
func fit_bar() -> void:
	var rails: bool = layout != null and layout.visible
	# A phone upright (the reduced layout, #28): touch-sized buttons 8 px apart, on two rows.
	var upright: bool = (
		panel.is_inside_tree() and LayoutMode.form_of(panel) == LayoutMode.Form.PHONE_PORTRAIT
	)
	var narrow: bool = panel.size.x < CommsPanel.NARROW_BAR and not rails and not upright
	var bar: HFlowContainer = panel._bar
	bar.add_theme_constant_override(
		"h_separation", UiTheme.TOUCH_GAP if upright else (3 if narrow else 6)
	)
	bar.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP if upright else 4)
	for b: Button in panel._buttons.values():
		if not rails:
			b.custom_minimum_size = (
				Vector2(UiTheme.TOUCH_PRIMARY, UiTheme.TOUCH_PRIMARY) if upright else Vector2.ZERO
			)
		if narrow:
			b.add_theme_font_size_override("font_size", 14)
			b.add_theme_stylebox_override("normal", _tight(b, "normal"))
		else:
			b.remove_theme_font_size_override("font_size")
			b.remove_theme_stylebox_override("normal")


## Each frame on a phone: the spacers under the view-top row and above the gesture band,
## and the conversation's place, a top-level control the panel doesn't clip: on its side
## over the board and the radar column, the rail staying live; upright over the board, the
## buttons and the radar column, down to the bottom tab bar (the buttons hide under it).
func place() -> void:
	var phone: bool = paged()
	var side: bool = landscape()
	var overlay: CommsOverlay = panel.overlay
	var open: bool = overlay.card_id >= 0
	if phone:
		top_gap.custom_minimum_size.y = panel.top_reserve
		# On its side the bar holds only the status line: shown while it says something.
		panel._bar.visible = panel._status.text != "" if side else not open
		var over: float = panel.get_global_rect().end.y - SafeArea.tap_bottom(panel)
		foot_gap.custom_minimum_size.y = maxf(0.0, over)
	panel.clip_contents = not phone
	overlay.fill = side
	if overlay.top_level != phone:
		overlay.top_level = phone
		if not phone:
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not phone:
		return
	var gap: float = UiTheme.TOUCH_GAP
	var safe: Rect2 = SafeArea.safe_rect(panel)
	var r: Rect2 = Rect2(panel._rows.global_position.x, panel.global_position.y + gap, 0.0, 0.0)
	r.end = Vector2(safe.end.x, SafeArea.tap_bottom(panel))
	if not side:
		r.position = panel.global_position + Vector2(0.0, panel.top_reserve)
		r.end = Vector2(panel.get_global_rect().end.x, _upright_floor() - gap)
	if overlay.global_position != r.position or overlay.size != r.size:
		overlay.global_position = r.position
		overlay.size = r.size


## Moves the buttons to the rail on a phone on its side, back under the board elsewhere.
func arrange_rails() -> void:
	var rails: bool = landscape()
	if rails == (layout != null and layout.visible):
		return
	var rows: VBoxContainer = panel._rows
	var order: Array[String] = ["hail", "accept", "decline", "claim", "hold_fire"]
	if rails:
		if layout == null:
			layout = RailLayout.new()
			layout.docked = true
			layout.offset_top = UiTheme.TOUCH_GAP
			panel.add_child(layout)
			layout.rail(SIDE_LEFT)
		layout.visible = true
		var gap: MarginContainer = MarginContainer.new()
		gap.add_theme_constant_override("margin_left", UiTheme.TOUCH_GAP)
		rows.reparent(gap, false)
		rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.set_content(gap)
		for id: String in order:
			var b: Button = panel._buttons[id]
			b.reparent(layout.left.box, false)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = UiTheme.TOUCH_PRIMARY
	else:
		layout.visible = false
		var gap: Control = rows.get_parent()
		rows.reparent(panel, false)
		panel.move_child(rows, 0)
		rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.remove_child(gap)
		gap.queue_free()
		var bar: HFlowContainer = panel._bar
		for id: String in order:
			var b: Button = panel._buttons[id]
			b.reparent(bar, false)
			b.size_flags_horizontal = Control.SIZE_FILL
			b.custom_minimum_size.y = 0.0
			bar.move_child(b, order.find(id))
	if panel.overlay != null:
		panel.move_child(panel.overlay, -1)


## Upright, where the conversation ends: the top of the screen's bottom tab bar, else the
## tap limit.
func _upright_floor() -> float:
	var n: Node = panel.get_parent()
	while n != null and not n is StationScreen:
		n = n.get_parent()
	var s: StationScreen = n as StationScreen
	if s != null and s.frame.bottom_tabs.is_visible_in_tree():
		return s.frame.bottom_tabs.get_global_rect().position.y
	return SafeArea.tap_bottom(panel)


## The button's own style with 6 px side margins.
static func _tight(b: Button, name: String) -> StyleBox:
	var box: StyleBox = b.get_theme_stylebox(name).duplicate()
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	return box
