class_name EngineeringTablet
extends RefCounted
## Engineering on a tablet (C4, the Helm and Weapons rail pattern of #32, D324): a TabletDock
## of two opaque rails at the screen's edges, the panel's desktop arrangement between them.
## Left rail: Power +/-, Tighter, Wider, Boost. Right rail: Harden,
## Repair, Cause, Probe and Claim. Upright the rails are one bottom bar with two columns of
## buttons each. Every button sends the intent of its key (EngineeringPanel.press_touch) and
## shows why it can't act now (EngineeringPanel.update_rails).

const LEFT_IDS: Array[String] = ["pip_add", "pip_remove", "shield_tighter", "shield_wider", "boost"]
const RIGHT_IDS: Array[String] = [
	"harden", "dispatch_nearest", "cause_next", "fabricate_probe", "claim"
]

var portrait: bool = false
var dock: TabletDock
## Intent id -> its rail button.
var buttons: Dictionary = {}


func _init(panel: EngineeringPanel, is_portrait: bool) -> void:
	portrait = is_portrait
	dock = TabletDock.new(portrait)
	dock.left.add(_group(panel, LEFT_IDS))
	dock.right.add(_group(panel, RIGHT_IDS))


## The buttons in a column (landscape) or a two-column grid (upright, where a rail is wide).
func _group(panel: EngineeringPanel, ids: Array[String]) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2 if portrait else 1
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	for id: String in ids:
		for a: Array in EngineeringPanel.TOUCH_ACTIONS:
			if a[0] != id:
				continue
			var b: RailButton = panel.rail_button(a)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			buttons[id] = b
			grid.add_child(b)
	return grid


## Builds, rebuilds (a rotation) or drops `p`'s tablet rails for the viewport's form: only the
## focused panel of a tablet, with a ship, gets them.
static func sync(p: EngineeringPanel, screen: StationScreen) -> void:
	if not p.is_inside_tree() or p.ship_def == null:
		return
	var want: bool = (
		p.focused
		and not p.docked
		and screen != null
		and LayoutMode.form_of(p) == LayoutMode.Form.TABLET
		and TabletDock.fits(LayoutMode.dp_size_of(p.get_viewport()))
	)
	var portrait: bool = want and LayoutMode.portrait(screen.size)
	var ui: EngineeringTablet = p.tablet_ui
	if ui != null and (not want or ui.portrait != portrait):
		if screen != null and screen.tablet_dock == ui.dock:
			screen.set_tablet_dock(null)
		ui.dock.queue_free()
		p.tablet_ui = null
	if want and p.tablet_ui == null:
		p.tablet_ui = EngineeringTablet.new(p, portrait)
		screen.set_tablet_dock(p.tablet_ui.dock)
		p.update_rails()
