class_name TabletDock
extends Control
## Helm's and Weapons' touch controls on a tablet (#32, D324): two opaque docked rails
## at the edges of the screen with the whole tablet screen between them (top bar, HUD, radar
## column and shield ring unobstructed; the rails shrink the screen, they never cover it).
## Upright, both rails join one docked bar along the bottom, each taking half of its width,
## sticks at the lower corners. The station fills `left` and `right` (TouchRail) and gives
## the dock to the StationScreen (`set_tablet_dock`), which reserves its room and places it.
## A station with buttons only (Engineering) asks for a compact bar of `bar` px instead, in
## either orientation: one row of buttons per half.
##
##     var dock := TabletDock.new(portrait)
##     dock.left.add(...)
##     screen.set_tablet_dock(dock)

## A side rail's width (landscape), px: 176 px with its padding, as the owner's mockups.
const RAIL_W: float = 176.0
## The bottom bar's height (upright), px.
const BAR_H: float = 300.0
## A stick's side at a rail's lower corner, px.
const STICK: float = 136.0

## The least side (device-independent px) of a window that gets a dock; a headless run's
## 64 px forced to a tablet gets none.
const MIN_SIDE: float = 300.0

var portrait: bool = false
## The bottom bar's height, px, or 0 for side rails (landscape Helm and Weapons).
var bar_h: float = 0.0
var left: TouchRail
var right: TouchRail


func _init(is_portrait: bool = false, bar: float = 0.0) -> void:
	portrait = is_portrait
	bar_h = bar if bar > 0.0 else (BAR_H if portrait else 0.0)
	name = "TabletDock"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left = TouchRail.new(SIDE_LEFT, true)
	right = TouchRail.new(SIDE_RIGHT, true)
	left.name = "RailL"
	right.name = "RailR"
	for r: TouchRail in [left, right]:
		r.custom_minimum_size.x = 0.0 if bar_h > 0.0 else RAIL_W
		add_child(r)
		# (a wrapped label is tall until it gets its width: once it shrinks, the rail goes back
		# to its place, or it stays taller and runs into the gesture band)
		r.minimum_size_changed.connect(_reput.bind(r), CONNECT_DEFERRED)


## A side rail's width inside its padding (px; the DockedRail panel's 4 px each side): what a
## control filling the rail gets.
static func inner_width() -> float:
	return RAIL_W - 8.0


## True when a window of `dp` device-independent px is big enough for a dock.
static func fits(dp: Vector2) -> bool:
	return minf(dp.x, dp.y) >= MIN_SIDE


## The room the screen gives the dock: a column at each side (landscape, x each), or a bar
## along the bottom (upright or compact, y).
func reserve() -> Vector2:
	return Vector2(0.0, bar_h) if bar_h > 0.0 else Vector2(RAIL_W, 0.0)


## Puts the rails in `area` (the screen's tap area, in the screen's coordinates).
func place(area: Rect2) -> void:
	if bar_h > 0.0:
		var half: float = floorf(area.size.x / 2.0)
		var y: float = area.end.y - bar_h
		_put(left, Rect2(area.position.x, y, half, bar_h))
		_put(right, Rect2(area.position.x + half, y, area.size.x - half, bar_h))
	else:
		_put(left, Rect2(area.position.x, area.position.y, RAIL_W, area.size.y))
		_put(right, Rect2(area.end.x - RAIL_W, area.position.y, RAIL_W, area.size.y))


func _put(r: TouchRail, rect: Rect2) -> void:
	r.set_anchors_preset(Control.PRESET_TOP_LEFT)
	r.set_meta(&"place", rect)
	r.position = rect.position
	r.size = rect.size


func _reput(r: TouchRail) -> void:
	if r.has_meta(&"place"):
		r.size = (r.get_meta(&"place") as Rect2).size


## Makes `s` a stick of `side` px that sits at its rail's lower corner: at the bottom of a
## landscape rail, at the outer end of an upright bar's rail (`outer_left`: the bar's left
## end). Call it after the stick is added to its rail, which fills the rail's width.
static func corner_stick(
	s: VirtualStick, portrait_bar: bool, outer_left: bool, side: float = STICK
) -> VirtualStick:
	s.custom_minimum_size = Vector2(side, side)
	s.size_flags_vertical = Control.SIZE_SHRINK_END
	if portrait_bar:
		s.size_flags_horizontal = (
			Control.SIZE_SHRINK_BEGIN if outer_left else Control.SIZE_SHRINK_END
		)
	return s
