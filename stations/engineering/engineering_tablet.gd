class_name EngineeringTablet
extends RefCounted
## Engineering on a tablet (C4, the Helm and Weapons rail pattern of #32, D324): a TabletDock
## of two opaque rails at the screen's edges, the panel's desktop arrangement between them.
## Left rail: Add power, Cut power, Focus shields, Widen shields, Boost engines. Right rail:
## Protect part, Repair part, and Guess cause, Build probe and Take crew while they matter
## (EngineeringModel.shown). In either orientation the rails are one compact bottom bar, so
## the panel keeps its height (w5: side rails or a 300 px bar squeezed the ship, power and
## faults): on its side a row of buttons per half, upright (too narrow for five labels of a
## verb and its object) two rows of three. Every button is a full touch target (R23-16),
## sends the intent of its key (EngineeringPanel.press_touch) and shows why it can't act now
## (EngineeringPanel.update_rails).

const LEFT_IDS: Array[String] = ["pip_add", "pip_remove", "shield_tighter", "shield_wider", "boost"]
const RIGHT_IDS: Array[String] = [
	"harden", "dispatch_nearest", "cause_next", "fabricate_probe", "claim"
]

## The compact bar's height on its side: one 48 px button row and the rail's padding.
const BAR_H: float = 64.0
## Upright: two rows and the gap between them.
const BAR_H_UPRIGHT: float = BAR_H + UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
## Upright, the buttons of a half in rows of this many.
const UPRIGHT_COLUMNS: int = 3

var portrait: bool = false
var dock: TabletDock
## Intent id -> its rail button.
var buttons: Dictionary = {}


func _init(panel: EngineeringPanel, is_portrait: bool) -> void:
	portrait = is_portrait
	dock = TabletDock.new(portrait, BAR_H_UPRIGHT if portrait else BAR_H)
	dock.left.add(_group(panel, LEFT_IDS))
	dock.right.add(_group(panel, RIGHT_IDS))


## The buttons of one half: one row on its side, rows of three upright. A hidden button
## leaves no gap (the grid closes up in order).
func _group(panel: EngineeringPanel, ids: Array[String]) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = UPRIGHT_COLUMNS if portrait else ids.size()
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
