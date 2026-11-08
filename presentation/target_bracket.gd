class_name TargetBracket
extends RefCounted
## Four corner brackets round a point (R05-5, G3): the Viewer's overlay and Weapons' turret
## view draw their contacts with them. The corners sit `r` px from the centre; each arm
## runs `arm` px along an edge.


## Brackets of half side `r` and arm length `arm` round `p`, lines `width` px wide.
static func draw(
	canvas: CanvasItem, p: Vector2, r: float, arm: float, col: Color, width: float
) -> void:
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner: Vector2 = p + Vector2(sx, sy) * r
			canvas.draw_line(corner, corner - Vector2(sx * arm, 0.0), col, width)
			canvas.draw_line(corner, corner - Vector2(0.0, sy * arm), col, width)
