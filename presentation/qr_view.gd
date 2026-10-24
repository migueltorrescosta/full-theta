class_name QrView
extends Control
## Draws a QR code (QrCode.encode) with the quiet zone of 4 modules the standard asks
## for: dark modules on a white background, whatever the theme.

const QUIET: int = 4

var modules: Array = []
var module_px: int = 6


func set_text(text: String) -> void:
	modules = QrCode.encode(text)
	var n: int = modules.size() + 2 * QUIET if not modules.is_empty() else 0
	custom_minimum_size = Vector2(n, n) * module_px
	queue_redraw()


func _draw() -> void:
	if modules.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color.WHITE)
	for y: int in modules.size():
		for x: int in modules.size():
			if modules[y][x]:
				var origin: Vector2 = Vector2(x + QUIET, y + QUIET) * module_px
				draw_rect(Rect2(origin, Vector2.ONE * module_px), Color.BLACK)
