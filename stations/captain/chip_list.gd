class_name ChipList
extends Control
## The Captain's read-only list of open request chips: "Helm > Engineering  boost  6 s"
## (FT-CPT-004). It takes rows as ChipSource returns them and answers no input.

const ROW_HEIGHT: float = 26.0
const HEADER_HEIGHT: float = 26.0
const FONT_SIZE: int = 15
const MAX_ROWS: int = 6

var rows: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEADER_HEIGHT + ROW_HEIGHT * MAX_ROWS)


## The row text: "Helm > Engineering  boost  6 s".
static func row_text(row: Dictionary) -> String:
	var path: String = (
		"%s > %s"
		% [
			TranslationServer.translate("station." + str(row["from"])),
			TranslationServer.translate("station." + str(row["to"])),
		]
	)
	var left: float = float(row.get("left_s", 0.0))
	var time: String = "  %d s" % ceili(left) if left > 0.0 else ""
	return "%s  %s%s" % [path, row["label"], time]


func show_rows(new_rows: Array[Dictionary]) -> void:
	if new_rows == rows:
		return
	rows = new_rows
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var header: String = TranslationServer.translate("captain.chips")
	draw_string(
		font,
		Vector2(0.0, font.get_ascent(FONT_SIZE) + 2.0),
		header,
		0,
		-1,
		FONT_SIZE,
		Palette.color("text_dim")
	)
	if rows.is_empty():
		var none: String = TranslationServer.translate("captain.no_chips")
		var base: Vector2 = Vector2(8.0, HEADER_HEIGHT + font.get_ascent(FONT_SIZE) + 4.0)
		draw_string(font, base, none, 0, size.x - 16.0, FONT_SIZE, Palette.color("text_dim"))
		return
	for i: int in mini(rows.size(), MAX_ROWS):
		var r: Rect2 = Rect2(0.0, HEADER_HEIGHT + i * ROW_HEIGHT, size.x, ROW_HEIGHT - 3.0)
		draw_rect(r, Palette.color("panel"))
		var base: Vector2 = Vector2(8.0, r.position.y + 3.0 + font.get_ascent(FONT_SIZE))
		draw_string(
			font, base, row_text(rows[i]), 0, size.x - 16.0, FONT_SIZE, Palette.color("text")
		)
