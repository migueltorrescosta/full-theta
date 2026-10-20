class_name AlertFlash
extends Control
## The screen-edge flash of an alert (FT-STN-004, FT-SIM-032): a coloured frame round the
## whole screen that fades over FLASH_MS. Drawn in 2D, cheap; never takes input.

const FLASH_MS: int = 700
const WIDTH: float = 10.0

## The last flash's colour.
var color: Color = Color.TRANSPARENT
var _from_ms: int = -FLASH_MS
var _alpha: float = 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func flash(c: Color, now_ms: int) -> void:
	color = c
	_from_ms = now_ms
	update(now_ms)


## Strength 1..0 of the flash at now_ms.
func strength(now_ms: int) -> float:
	return clampf(1.0 - float(now_ms - _from_ms) / float(FLASH_MS), 0.0, 1.0)


func update(now_ms: int) -> void:
	var a: float = strength(now_ms)
	if a != _alpha:
		_alpha = a
		queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var c: Color = Color(color, 0.8 * _alpha)
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(-WIDTH / 2.0), c, false, WIDTH)
