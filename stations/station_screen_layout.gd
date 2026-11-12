class_name StationScreenLayout
extends RefCounted
## The layout half of a StationScreen (R13-1): builds its widgets and arranges them for the
## viewport (LayoutMode), the radar column, the share drawer and the dev seat's tab strip.
## The widgets stay fields of the screen (`s`), which tests and panels read.

var s: StationScreen


func _init(screen: StationScreen) -> void:
	s = screen


## The room the tablet dock takes (x at each side, or y at the bottom); zero without one.
func dock_reserve() -> Vector2:
	return s.tablet_dock.reserve() if s.tablet_dock != null else Vector2.ZERO


## The radar column hides for a lone full-screen panel (which may depend on the form). A
## joint view or the dev seat on a phone on its side (#28) shows only the focused panel,
## which gets the whole width when it draws its own rails and radar, and the station chip
## in the top bar's tab strip instead of the docked panels (FT-JNT-001: tap to focus). On
## a phone on its side the share buttons move into a drawer
## (D274: 48 px with 8 px gaps don't fit under the disc); its opener sits at the top of the
## radar column or, with the column hidden, at the bottom centre of the main area (clear of
## the rails); a panel may take the opener into its rails (StationPanel.share_slot) or show
## the buttons itself. Off a phone a full-screen panel hides the column and holds the buttons
## in its StationPanel.share_home.
func show_side() -> void:
	if s.panels.is_empty():
		return
	var form_now: LayoutMode.Form = (
		LayoutMode.form_of(s) if s.is_inside_tree() else LayoutMode.Form.DESKTOP
	)
	var sideways: bool = form_now == LayoutMode.Form.PHONE_LANDSCAPE
	var phone_form: bool = LayoutMode.is_phone(form_now)
	# Upright a joint view keeps its docked panels until the stations' upright layouts
	# leave room for the bottom tab bar (#28 follow-up, wave 2).
	var phone_alone: bool = s.panels.size() >= 2 and sideways
	var alone: bool = s.panels.size() == 1 or phone_alone
	s._side.visible = not (alone and s.focused_panel().full_screen())
	s._dock.visible = not phone_alone
	for p: StationPanel in s.panels:
		if p.docked:
			var least: float = StationScreen.DOCK_MIN_HEIGHT if p.shows_docked() else 0.0
			p.custom_minimum_size.y = least
	if s._tabs != null:
		s._tabs.visible = not phone_form
	s.frame.show_tabs(form_now, phone_alone)
	# Off a phone a full-screen panel (Science alone) holds the buttons in its share_home, so
	# they stay on screen without the radar column (D217, #35 A11).
	var home: Container = null if s._side.visible or phone_form else s.focused_panel().share_home
	# Also in the drawer whenever a phone's radar column is hidden (Science alone upright).
	var in_drawer: bool = sideways or (not s._side.visible and home == null)
	var parent: Control = (
		s.share_drawer.body if in_drawer else (home if home != null else s._extras)
	)
	if s.share_bar.get_parent() != parent:
		s.share_bar.reparent(parent, false)
		if parent == s._extras:
			s._extras.move_child(s.share_bar, s._extras_pad.get_index() + 1)
	if in_drawer:
		s.share_bar.min_width = TouchDrawer.WIDTH - 2.0 * UiTheme.TOUCH_GAP
	elif home != null and s.focused_panel().share_home_width > 0.0:
		# A tablet's rail (C14): as wide as the rail, at the touch sizes (D274).
		s.share_bar.min_width = s.focused_panel().share_home_width
		s.share_bar.button_h = UiTheme.TOUCH_PRIMARY
		s.share_bar.gap = UiTheme.TOUCH_GAP
	sync_share()
	_place_phone_bar()
	_place_training(
		not phone_form and s._side.visible and s.training != null and not s.training.touch_layout()
	)


## True while the radar column shows (a full-screen panel alone hides it and, on a tablet,
## draws its radar as an inset on its view, C14).
func side_shown() -> bool:
	return s._side != null and s._side.visible


## The side column scrolls in whole rows: the room under the last row that fits is a margin.
func snap_side() -> void:
	if s._side_margin != null and s.is_inside_tree():
		ScrollSnap.fit(s._side_scroll, s._side_margin, s._extras)


## The Shakedown card sits at the top of the side column when there is one (it then covers
## no gauge), else floats over the screen.
func _place_training(in_column: bool) -> void:
	if s.training == null:
		return
	if in_column and s.training.get_parent() != s._extras:
		s.training.reparent(s._extras, false)
		s._extras.move_child(s.training, 0)
		s.training.dock(true)
	elif not in_column and s.training.get_parent() != s:
		s.training.reparent(s, false)
		s.training.dock(false)


## The opener shows while the share buttons sit in the drawer and there is something to
## share; the drawer closes when there isn't.
func sync_share() -> void:
	var want: bool = (
		s.share_bar.get_parent() == s.share_drawer.body
		and s.share_bar.visible
		and not s.focused_panel().shows_shares
	)
	if not want:
		s.share_drawer.close()
	if s.share_opener.visible != want or s.share_opener.get_parent() != _opener_home():
		s.share_opener.visible = want
		_place_phone_bar()


## The opener's container: the panel's slot in its rails while the radar column is hidden
## (Science), else the bar with the joint switch.
func _opener_home() -> Container:
	var slot: Container = null if s._side.visible else s.focused_panel().share_slot
	return slot if slot != null else s._phone_bar


func _place_phone_bar() -> void:
	var home: Container = _opener_home()
	if s.share_opener.get_parent() != home:
		if s.share_opener.get_parent() != null:
			s.share_opener.get_parent().remove_child(s.share_opener)
		home.add_child(s.share_opener)
	s.share_opener.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shown: bool = s.share_opener.visible and home == s._phone_bar
	s._phone_bar.visible = shown
	var in_side: bool = s._side.visible
	for p: StationPanel in s.panels:
		var reserve: float = 0.0
		if shown and not in_side and p == s.focused_panel():
			reserve = UiTheme.TOUCH_PRIMARY + 2.0 * UiTheme.TOUCH_GAP + s._band_h
		if p.bottom_reserve != reserve:
			p.bottom_reserve = reserve
			p.queue_redraw()
	var parent: Control = s._extras if in_side else s._main
	if s._phone_bar.get_parent() != parent:
		s._phone_bar.reparent(parent, false)
	s._phone_bar.vertical = in_side
	var w: float = (
		StationScreen.OPENER_W
		if s.share_opener.get_parent() == s._phone_bar and not in_side
		else 0.0
	)
	s.share_opener.custom_minimum_size = Vector2(w, UiTheme.TOUCH_PRIMARY)
	if in_side:
		s._extras.move_child(s._phone_bar, 0)
	else:
		s._phone_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		s._phone_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		s._phone_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		s._phone_bar.offset_bottom = -UiTheme.TOUCH_GAP - s._band_h
	# The drawer: beside the radar column, or centred above the bar; never in the band.
	var half: float = TouchDrawer.WIDTH / 2.0
	s.share_drawer.anchor_top = 0.0
	s.share_drawer.anchor_bottom = 1.0
	s.share_drawer.offset_top = UiTheme.TOUCH_GAP
	if in_side:
		s.share_drawer.anchor_left = 1.0
		s.share_drawer.anchor_right = 1.0
		s.share_drawer.offset_right = -UiTheme.TOUCH_GAP
		s.share_drawer.offset_left = -UiTheme.TOUCH_GAP - TouchDrawer.WIDTH
		s.share_drawer.offset_bottom = -s._band_h
	else:
		s.share_drawer.anchor_left = 0.5
		s.share_drawer.anchor_right = 0.5
		s.share_drawer.offset_left = -half
		s.share_drawer.offset_right = half
		s.share_drawer.offset_bottom = -UiTheme.TOUCH_PRIMARY - 2.0 * UiTheme.TOUCH_GAP - s._band_h
	raise_overlays()


## Keeps the main area's overlays over the focused panel, in order: the bottom bar, the
## share drawer, the view-top row, the choice sheet on top.
func raise_overlays() -> void:
	for c: Control in [s._phone_bar, s.share_drawer, s.frame.view_top, s.sheet]:
		if c != null and c.get_parent() == s._main:
			s._main.move_child(c, -1)


## The dev seat's station switcher: a tab per panel, numbered for Shift + digit, and until the
## first switch a one-line hint (kept in the first-run tips).
func build_tabs() -> void:
	if s.panels.size() < StationScreen.TABS_FROM:
		return
	s._tabs = HFlowContainer.new()
	s._tabs.add_theme_constant_override("h_separation", 4)
	s._tabs.add_theme_constant_override("v_separation", 2)
	s.top_bar.get_parent().add_child(s._tabs)
	s.top_bar.get_parent().move_child(s._tabs, s.top_bar.get_index() + 1)
	for i: int in s.panels.size():
		var b: Button = Button.new()
		b.name = "Tab%d" % (i + 1)
		b.toggle_mode = true
		b.text = "%d %s" % [i + 1, s.tr("station." + s.stations[i])]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(s.focus.bind(i))
		s._tabs.add_child(b)
	s._hint = Label.new()
	s._hint.text = s.tr("screen.tabs_hint") % s.panels.size()
	s._hint.add_theme_color_override("font_color", Palette.color("text_dim"))
	s._hint.visible = not s.ctx.settings.hint_seen(StationScreen.TAB_HINT_KEY)
	s._hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s._tabs.add_child(s._hint)


## Marks the focused tab; a switch after the first panel retires the hint.
func show_tabs() -> void:
	for i: int in s.panels.size():
		(s._tabs.get_child(i) as Button).set_pressed_no_signal(i == s.focus_index)
	if s._hint.visible and s.focus_index != 0:
		s._hint.visible = false
		s.ctx.settings.mark_hint_seen(StationScreen.TAB_HINT_KEY)
		s.ctx.settings.save()


func build() -> void:
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.add_child(bg)
	# Everything but the background and the flash stays inside the safe area (#28).
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	s.add_child(rows)
	s._rows = rows
	s.top_bar = TopBar.new()
	s.top_bar.custom_minimum_size = Vector2(0, StationScreen.TOP_BAR_HEIGHT)
	s.top_bar.alert_picked.connect(s.common.set_alert)
	s.top_bar.fullscreen.visibility_changed.connect(relayout, CONNECT_DEFERRED)
	rows.add_child(s.top_bar)
	s.rotate_banner = RotateBanner.new()
	rows.add_child(s.rotate_banner)
	s._body = BoxContainer.new()
	s._body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(s._body)
	s._main = Control.new()
	s._main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s._main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s._main.clip_contents = true
	s._body.add_child(s._main)
	s._side = BoxContainer.new()
	s._body.add_child(s._side)
	s.radar = DiscRadar.new()
	s._side.add_child(s.radar)
	# The column scrolls instead of growing the screen past the viewport (150 % UI scale,
	# a phone with four share buttons): the radar keeps its size, the rest is reachable.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A wide bar shows at a glance that the column scrolls.
	scroll.get_v_scroll_bar().custom_minimum_size.x = StationScreen.SCROLL_BAR_W
	# The margin under the scroll makes its last visible row whole at rest (snap_side).
	s._side_margin = MarginContainer.new()
	s._side_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s._side_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s._side_margin.add_child(scroll)
	s._side.add_child(s._side_margin)
	s._side_scroll = scroll
	s._extras = VBoxContainer.new()
	s._extras.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s._extras.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(s._extras)
	scroll.resized.connect(snap_side.call_deferred)
	s._extras.minimum_size_changed.connect(snap_side.call_deferred)
	# Upright on a phone the column sits under the panel's thumb controls: keep 8 px.
	s._extras_pad = Control.new()
	s._extras_pad.custom_minimum_size.y = UiTheme.TOUCH_GAP / 2.0
	s._extras_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s._extras_pad.visible = false
	s._extras.add_child(s._extras_pad)
	# The share buttons sit above the docked panels, not over them (D217).
	s.share_bar = ShareBar.new()
	s.share_bar.visible = false
	s.share_bar.share_pressed.connect(func(id: StringName) -> void: s.ctx.intents.share(String(id)))
	s._extras.add_child(s.share_bar)
	s._dock = VBoxContainer.new()
	s._dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s._extras.add_child(s._dock)
	# On a phone on its side the column stops above the gesture band (P28-Band).
	s._side_band = Control.new()
	s._side_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s._side.add_child(s._side_band)
	var share_text: String = TouchText.of("share.drawer", "Share")
	s.share_drawer = TouchDrawer.new(share_text, SIDE_RIGHT)
	s.share_drawer.name = "ShareDrawer"
	s._main.add_child(s.share_drawer)
	s.share_opener = RailButton.make(share_text + " ▸")
	s.share_opener.name = "ShareOpener"
	s.share_opener.visible = false
	s.share_drawer.bind_opener(s.share_opener)
	s._phone_bar = BoxContainer.new()
	s._phone_bar.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	s._phone_bar.visible = false
	s._phone_bar.add_child(s.share_opener)
	s._extras.add_child(s._phone_bar)
	s.toasts = Toasts.new()
	s.add_child(s.toasts)
	s.chip_strip = ChipStrip.new()
	s.chip_strip.position = Vector2(8.0, StationScreen.TOP_BAR_HEIGHT + 8.0)
	s.chip_strip.visible = false
	s.add_child(s.chip_strip)
	s.flash = AlertFlash.new()
	s.flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.add_child(s.flash)
	s.sheet = ChoiceSheet.new()
	s.sheet.name = "Sheet"
	s._main.add_child(s.sheet)
	s.frame.build(s, s._main, rows)
	s.top_bar.menu_pressed.connect(s._open_menu)
	# After a handover the bar names the ship this player now watches (R24-18).
	# (a method, not a lambda: a lambda would keep this layout alive with the crew state)
	s.ctx.crew.changed.connect(_on_crew_changed)
	show_watching()


func _on_crew_changed(_what: StringName) -> void:
	show_watching()


## The top bar names the watched ship while the player's own ship is out (a handover to
## another ship, D91, R24-18) and they watch it; a guest seated at one of its stations is
## crew there, so the bar names the ship as its own (#40 D10).
func show_watching() -> void:
	var h: Dictionary = s.ctx.crew.handover
	var to: int = int(h.get("to_ship", FleetMessages.TO_SCOREBOARD))
	var watching: bool = to != FleetMessages.TO_SCOREBOARD
	watching = watching and s.ctx.crew.seat == StationCatalogue.VIEWER
	s.top_bar.watching = s.ctx.crew.ship_name(to) if watching else ""
	s.top_bar.bots = LobbySeatGrid.bots_line(s.ctx)  # the ship's bots (#40 D1)


## P28-Band: on a phone on its side a panel in the frame (StationPanel.in_frame) draws into
## the bottom band; the band takes no taps (PhoneFrame.band_guard), and the side column,
## the share opener and the sheet stay above it.
func apply_band() -> void:
	if s._body == null or not s.is_inside_tree() or s.panels.is_empty():
		return
	var bottom: float = maxf(SafeArea.margins(s).w, SafeArea.tap_band(s))
	var sideways: bool = LayoutMode.form_of(s) == LayoutMode.Form.PHONE_LANDSCAPE
	var into: bool = s.phone and sideways and s.focused_panel().in_frame
	s._band_h = bottom if into else 0.0
	# (outside the band the rows keep EDGE_GAP above the screen's edge, so a bottom row
	# never sits flush with it)
	s._rows.offset_bottom = (
		-(0.0 if into else maxf(bottom, StationScreen.EDGE_GAP)) - dock_reserve().y
	)
	s._side_band.custom_minimum_size.y = s._band_h
	s.sheet.offset_bottom = -s._band_h


## Arranges the screen for the viewport (LayoutMode): the bar's height and rows, and the
## radar column beside the main area (landscape) or below it (portrait), narrower or
## shorter on a phone. Runs on every resize and rotation.
func relayout() -> void:
	if s._body == null or not s.is_inside_tree():
		return
	var size_now: Vector2 = s.get_viewport().get_visible_rect().size
	var kind: LayoutMode.Kind = LayoutMode.kind_of(s)
	# The safe area: on a phone also clear of the gesture band, so nothing on the screen
	# can be tapped there (#28).
	var m: Vector4 = SafeArea.margins(s)
	var bottom: float = maxf(m.w, SafeArea.tap_band(s))
	var res: Vector2 = dock_reserve()
	s._rows.offset_left = m.x + res.x
	s._rows.offset_top = m.y
	s._rows.offset_right = -m.z - res.x
	s._rows.offset_bottom = -maxf(bottom, StationScreen.EDGE_GAP) - res.y
	size_now -= Vector2(m.x + m.z, m.y + bottom)
	if s.tablet_dock != null:
		s.tablet_dock.place(Rect2(m.x, m.y, size_now.x, size_now.y))
	var touch: bool = LayoutMode.is_touch(kind)
	var portrait: bool = LayoutMode.portrait(size_now)
	var kind_form: LayoutMode.Form = LayoutMode.Form.TABLET if touch else LayoutMode.Form.DESKTOP
	s.phone = s.phone_frame()
	s.frame.band_guard.visible = s.phone
	s.frame.band_guard.offset_top = -bottom
	s.sheet.upright = portrait
	if not s.phone:
		s.sheet.cancel()
	apply_band()
	s._body.vertical = portrait
	s._side.vertical = not portrait
	var bar: float = StationScreen.TOP_BAR_HEIGHT
	if s.phone:
		bar = StationScreen.PHONE_BAR_HEIGHT
	elif touch:
		bar = StationScreen.TOUCH_BAR_HEIGHT
	# The full-screen icon is 48 px tall: the bar makes room for it (D323).
	if s.top_bar.fullscreen.visible:
		bar = maxf(bar, StationScreen.FULLSCREEN_BAR_HEIGHT)
	var two_rows: bool = (
		size_now.x < (StationScreen.COMPACT_PHONE_WIDTH if s.phone else StationScreen.COMPACT_WIDTH)
	)
	if res.x > 0.0:
		# Between a tablet's side rails (an iPad's 828 px fits one row, 672 px doesn't).
		two_rows = size_now.x - 2.0 * res.x < StationScreen.DOCK_COMPACT_WIDTH
	if s.phone:
		# The phone's one-row bar (design 1.2).
		two_rows = false
	# (the screen's phone frame decides the phone bar; a headless window too small to be a
	# phone still gets a desktop bar)
	var bar_form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE if s.phone else kind_form
	s.top_bar.apply(bar_form, two_rows, bar)
	s.top_bar.custom_minimum_size.y = bar * (2.0 if two_rows else 1.0) + s.top_bar.goal_height()
	var disc: float = StationScreen.RADAR_HEIGHT
	var short: bool = size_now.y < StationScreen.SHORT_H and not s.phone
	if s.phone:
		disc = StationScreen.PHONE_RADAR
	elif short:
		disc = StationScreen.SHORT_RADAR
	s._side.custom_minimum_size = Vector2.ZERO
	if portrait:
		s.radar.custom_minimum_size = Vector2(disc, disc)
		s._side.custom_minimum_size.y = disc
	else:
		var width: float = StationScreen.PHONE_SIDE_WIDTH if s.phone else StationScreen.SIDE_WIDTH
		if short and size_now.x < StationScreen.COMPACT_WIDTH:
			width = StationScreen.SHORT_SIDE_WIDTH
		s.radar.custom_minimum_size = Vector2(width, disc if not s.phone else width)
		s._side.custom_minimum_size.x = width
	s.share_bar.min_width = 150.0 if s.phone else 260.0
	s.share_bar.button_h = ShareBar.SHORT_H if short and not touch else ShareBar.BUTTON_H
	s.share_bar.gap = ShareBar.GAP
	if s.phone:
		# 48 px with 8 px gaps (D274); in the share drawer one a row (show_side).
		s.share_bar.button_h = UiTheme.TOUCH_PRIMARY
		s.share_bar.gap = UiTheme.TOUCH_GAP
	s._extras_pad.visible = s.phone and portrait
	var top: float = m.y + s.top_bar.custom_minimum_size.y + 8.0
	s.chip_strip.position = Vector2(8.0 + m.x + res.x, top)
	s.rotate_banner.visible = false
	if s.rotate_prompt:
		s.rotate_banner.refresh()
	show_side()
	var now: LayoutMode.Form = LayoutMode.form_of(s)
	if now != s.form:
		s.form = now
		s.form_changed.emit(s.form)
		# (a panel that rebuilt its pages for the new form gets its tabs bound)
		s.pages_changed()
