class_name RadarInset
extends PanelContainer
## A disc radar over a view in a translucent panel (the OverlayRail variation): Helm's Radar
## page and Weapons' inset on a phone (#28, FT-WPN-002), and on a tablet both stations'
## radar in a corner of the view, with no radar column (C14). A finger on it is the radar's,
## never the view's (TouchInput.GROUP): a finger lifted on a blip, or a mouse click on it,
## selects the blip within REACH px; the range label steps the range (DiscRadar).
##
##     var inset := RadarInset.new(ctx)
##     add_child(inset)
##     inset.refresh()  # once a frame while shown

## How far (px) a tap on the radar reaches for a blip.
const REACH: float = 24.0
## A tablet's corner inset: this share of the view's width, between CORNER_MIN and
## CORNER_MAX px, CORNER_ASPECT as tall as wide (a disc of about 100 px radius on a
## 1024x768 iPad, so its chips keep the full callout), at most CORNER_MAX_H of the view's height.
const CORNER_SHARE: float = 0.38
const CORNER_MIN: float = 240.0
const CORNER_MAX: float = 320.0
const CORNER_ASPECT: float = 0.85
const CORNER_MAX_H: float = 0.45

var radar: DiscRadar = DiscRadar.new()

var _ctx: StationContext


func _init(ctx: StationContext) -> void:
	_ctx = ctx
	name = "RadarInset"
	theme_type_variation = "OverlayRail"
	add_to_group(TouchInput.GROUP)
	radar.name = "Radar"
	radar.gui_input.connect(_on_radar_input)
	add_child(radar)


## The radar's picture and the selection, from the context (call while shown).
func refresh() -> void:
	if is_visible_in_tree():
		radar.set_picture(_ctx.picture(), _ctx.crew.selection, _ctx)


## The tablet inset's box in `view` (a station's view between its rails, C14): its top
## right corner, UiTheme.TOUCH_GAP in from the edges.
static func corner_rect(view: Rect2) -> Rect2:
	var gap: float = UiTheme.TOUCH_GAP
	var w: float = roundf(clampf(view.size.x * CORNER_SHARE, CORNER_MIN, CORNER_MAX))
	var h: float = roundf(minf(w * CORNER_ASPECT, view.size.y * CORNER_MAX_H))
	return Rect2(Vector2(view.end.x - gap - w, view.position.y + gap), Vector2(w, h))


## Puts the inset at `box` (its parent's coordinates).
func place(box: Rect2) -> void:
	box = Rect2(box.position.round(), box.size.round())
	if position != box.position or size != box.size:
		position = box.position
		size = box.size


## A finger lifted on a blip (or a mouse click; the mouse a finger emulates is left to the
## range label) selects it.
func _on_radar_input(event: InputEvent) -> void:
	var at: Vector2
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if t != null and not t.pressed:
		at = t.position
	elif (
		mb != null
		and mb.pressed
		and mb.button_index == MOUSE_BUTTON_LEFT
		and not TouchInput.is_emulated(mb)
	):
		at = mb.position
	else:
		return
	var item: Dictionary = radar.item_at(at, REACH)
	if not item.is_empty() and item["kind"] != "point":
		_ctx.crew.select(item["kind"], item["id"])
		radar.accept_event()
