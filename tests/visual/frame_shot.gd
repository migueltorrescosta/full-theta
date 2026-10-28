## The shared phone frame for the L5 harness (#28 follow-up, design "Shared frame"): a
## StationScreen of `entry` whose panels join the frame (StationPanel.in_frame), with a demo
## panel for a single station that has three pages over overlay rails and a Crew page
## (FrameDemo; the real stations get theirs in wave 2). Extras from shots.json: `insets`
## (SafeArea.simulate, drawn in translucent red with the band), `page` (the demo's page),
## `chip` (an incoming request chip from Helm), `ping` (a contact Bo pinged), `focus` (a
## joint view's focused panel) and `sheet` ("selection", "alert" or "stations": that sheet
## open).
extends Control

var entry: String = "engineering"
var insets: Array = []
var page: int = 0
var chip: bool = false
var ping: int = -1
var focus: int = 0
var sheet: String = ""

var _ctx: StationContext


## A single station's demo panel (Engineering-like): a radar view, a persistent column
## (Boost, Harden), the page zone (Power, Ship, Crew). On its side the view is between
## overlay rails; upright the view is on top and the controls block under it.
class FrameDemo:
	extends StationPanel

	var upright: bool = false
	var radar: DiscRadar = DiscRadar.new()

	func _setup() -> void:
		in_frame = true
		radar.set_picture(ctx.picture(), ctx.crew.selection)
		var keep: Array[RailButton] = [
			RailButton.make("Boost", RailButton.Role.ACCENT), RailButton.make("Harden")
		]
		var zone: VBoxContainer = VBoxContainer.new()
		zone.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages = PageHost.new()
		for t: Array in [["Power +", "Power −", "Tighter", "Wider"], ["Send crew", "Probe"]]:
			var grid: GridContainer = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
			grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
			for label: String in t:
				var b: RailButton = RailButton.make(label)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(b)
			zone.add_child(grid)
			pages.add_page("Power" if t.size() == 4 else "Ship", [grid])
		var crew: CrewPage = CrewPage.new(self)
		zone.add_child(crew)
		pages.add_page(TouchText.of("page.crew", "Crew"), [crew])
		if upright:
			var col: VBoxContainer = VBoxContainer.new()
			col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
			add_child(col)
			radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
			col.add_child(radar)
			var block: HBoxContainer = HBoxContainer.new()
			block.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
			block.custom_minimum_size.y = 240.0
			col.add_child(block)
			var left: VBoxContainer = VBoxContainer.new()
			left.custom_minimum_size.x = 120.0
			for b: RailButton in keep:
				left.add_child(b)
			block.add_child(left)
			block.add_child(zone)
			return
		var layout: RailLayout = RailLayout.new()
		add_child(layout)
		layout.set_content(radar)
		for b: RailButton in keep:
			layout.rail(SIDE_LEFT).add(b)
		var right: TouchRail = layout.rail(SIDE_RIGHT)
		right.custom_minimum_size.x = 168.0
		right.add(zone)

	## Upright the view is the radar above the controls block.
	func view_rect() -> Rect2:
		return radar.get_rect() if upright else super()

	## Like the real phone stations, the demo draws its own radar: no radar column.
	func full_screen() -> bool:
		return true


func _ready() -> void:
	SafeArea.simulate(insets)
	I18n.apply("en")
	LayoutMode.apply(get_tree().root)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ctx = StationFixture.context(entry, "user://l5_frame_shot.cfg")
	_ctx.crew.select("contact", StationFixture.H2)
	var s: StationScreen = StationScreen.new()
	if StationViews.CREW.has(entry):
		s.panel_factory = func(_id: String) -> StationPanel: return _demo()
	s.setup(_ctx)
	for p: StationPanel in s.panels:
		p.in_frame = true
	add_child(s)
	s.focus(focus)
	if s.focused_panel().pages != null:
		s.focused_panel().pages.current = page
	if chip:
		_ctx.view.blocks[StationViews.Section.CHIPS] = {"chips": [_chip_row()]}
	if ping >= 0:
		var p: Dictionary = {"ship": 0, "kind": "contact", "id": ping, "by": "Bo"}
		_ctx.crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS - 500)
	match sheet:
		"selection":
			s.frame.open_selection_sheet()
		"alert":
			s.frame.open_alert_sheet()
		"stations":
			s.joint_switch.pressed.emit()
	if not insets.is_empty():
		var shade: Control = load("res://tests/visual/station_shot.gd").InsetShade.new()
		shade.set("insets", insets)
		add_child(shade)


func _demo() -> FrameDemo:
	var d: FrameDemo = FrameDemo.new()
	d.upright = get_viewport_rect().size.y > get_viewport_rect().size.x
	return d


## An open Boost request from Helm to Engineering, or the first chip to the focused station.
func _chip_row() -> Dictionary:
	var chips: Array[ChipDef] = NetChips.def().chips
	var to: String = _ctx.crew.stations()[focus] if not _ctx.crew.stations().is_empty() else "helm"
	for i: int in chips.size():
		if String(chips[i].to_station) == to:
			return {
				"id": 5,
				"chip": i,
				"arg": -1,
				"from": StationViews.CREW.find(String(chips[i].from_station)),
				"to": StationViews.CREW.find(to),
				"sent": StationFixture.TICK - 240,
				"expires": StationFixture.TICK + 1080,
			}
	return {}


func _exit_tree() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
