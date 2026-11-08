class_name EngineeringTablet
extends RefCounted
## Engineering on a tablet (C4, the Helm and Weapons rail pattern of #32, D324): a TabletDock
## of two opaque rails at the screen's edges, the panel's desktop arrangement between them.
## Left rail: Power +/-, Tighter, Wider, Boost. Right rail: Harden,
## Repair, Cause, Probe and Claim. In either orientation the rails are one compact bottom bar,
## a row of buttons per half, so the panel keeps its height (w5: side rails or a 300 px bar
## squeezed the ship, power and faults). Every button sends the intent of its key
## (EngineeringPanel.press_touch) and shows why it can't act now (EngineeringPanel.update_rails).

const LEFT_IDS: Array[String] = ["pip_add", "pip_remove", "shield_tighter", "shield_wider", "boost"]
const RIGHT_IDS: Array[String] = [
	"harden", "dispatch_nearest", "cause_next", "fabricate_probe", "claim"
]

## The compact bar's height: one 48 px button row and the rail's padding.
const BAR_H: float = 64.0

var portrait: bool = false
var dock: TabletDock
## Intent id -> its rail button.
var buttons: Dictionary = {}


func _init(panel: EngineeringPanel, is_portrait: bool) -> void:
	portrait = is_portrait
	dock = TabletDock.new(portrait, BAR_H)
	dock.left.add(_group(panel, LEFT_IDS))
	dock.right.add(_group(panel, RIGHT_IDS))


## The buttons in one row.
func _group(panel: EngineeringPanel, ids: Array[String]) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = ids.size()
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	for id: String in ids:
		for a: Array in EngineeringPanel.TOUCH_ACTIONS:
			if a[0] != id:
				continue
			var b: RailButton = EngineeringPhone.rail_button(panel, a)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			buttons[id] = b
			grid.add_child(b)
	return grid
