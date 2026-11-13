class_name FullscreenToggle
extends FullscreenButton
## The top bar's full-screen button (D323): a 48 px icon, four corner brackets pointing out
## to enter and in to leave, at the right of the bar on every station screen and the lobby,
## on Android phones, tablets and desktops in a browser; never on an iPhone, whose browser
## can't (D277), and not in a native window, which has its own window controls. It toggles:
## the page acts on the tap itself (FullscreenButton), so it enters and leaves from the
## tap's own handler. The ☰ menu keeps its own Full screen entry.

const ACTION: String = "fullscreen_toggle"
## Corner bracket arm length and line width (px).
const ARM: float = 6.0
const WIDTH: float = 2.0
const INSET: float = 13.0

## Tests and L5 shots: 1 forces fullscreen on (the exit icon), 0 off, -1 asks the page.
static var forced_on: int = -1


func _init() -> void:
	super()
	name = "FullscreenToggle"
	action = ACTION
	custom_minimum_size = Vector2(UiTheme.TOUCH_PRIMARY, UiTheme.TOUCH_PRIMARY)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tooltip_text = tr(TEXT_KEY)
	draw.connect(_draw_icon)


## Whether the toggle is offered here: a browser that has fullscreen and isn't an iPhone's.
static func available() -> bool:
	if FullscreenButton.forced >= 0:
		return FullscreenButton.forced == 1
	return TouchPage.fullscreen_toggle_offered()


## True while the page or the window is fullscreen.
static func is_full() -> bool:
	if forced_on >= 0:
		return forced_on == 1
	return TouchPage.is_fullscreen()


func _label() -> String:
	return ""


func _is_offered() -> bool:
	return available()


func _refresh() -> void:
	super()
	tooltip_text = tr("touch.fullscreen_exit" if is_full() else TEXT_KEY)
	queue_redraw()


func _draw_icon() -> void:
	var c: Color = get_theme_color("font_color")
	var r: Rect2 = Rect2(Vector2.ONE * INSET, size - Vector2.ONE * 2.0 * INSET)
	var leave: bool = is_full()
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var p: Vector2 = r.position + r.size * corner
		var sx: float = 1.0 if corner.x == 0.0 else -1.0
		var sy: float = 1.0 if corner.y == 0.0 else -1.0
		var points: PackedVector2Array
		if leave:
			# The elbows sit inside and the arms reach the edges: shrink back.
			var e: Vector2 = p + Vector2(sx, sy) * ARM
			points = PackedVector2Array([e - Vector2(sx * ARM, 0.0), e, e - Vector2(0.0, sy * ARM)])
		else:
			# The elbows sit in the corners and the arms run along the edges: grow.
			points = PackedVector2Array([p + Vector2(sx * ARM, 0.0), p, p + Vector2(0.0, sy * ARM)])
		draw_polyline(points, c, WIDTH, true)
