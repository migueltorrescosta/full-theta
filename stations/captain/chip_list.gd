class_name ChipList
extends Control
## The Captain's read-only list of open request chips (FT-CPT-004): each row reads
## "Helm > Engineering  Boost", then "waiting, 6 s left" over a bar that runs out with it. It reads the CHIPS block through ChipView (`open_rows`) and answers no input.
##
## A row: {"from": station id, "to": station id, "label": text, "left_s": seconds left}.

const ROW_HEIGHT: float = 46.0
const TIME_FONT_SIZE: int = 13
const HEADER_HEIGHT: float = 26.0
const FONT_SIZE: int = 15
const MAX_ROWS: int = 6

var rows: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()


## The height of the rows shown (at least one), so a short list leaves the panel unscrolled.
func _fit() -> void:
	custom_minimum_size = Vector2(0, HEADER_HEIGHT + ROW_HEIGHT * clampi(rows.size(), 1, MAX_ROWS))


## Rows of the view's CHIPS block: all of the ship's open chips (the Captain sees them
## all), with the text in the session language and the seconds left.
static func open_rows(view: NetViewState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chip: Dictionary in ChipView.open_chips(view):
		var callsign: String = view.callsign(int(chip["arg"])) if int(chip["arg"]) >= 0 else ""
		(
			out
			. append(
				{
					"from": chip["from"],
					"to": chip["to"],
					"label": ChipView.label(chip, callsign),
					"left_s": ChipView.left_s(view, chip),
					"total_s":
					maxf(float(int(chip["expires"]) - int(chip["sent"])) / ChipView.HZ, 1.0),
				}
			)
		)
	return out


## The row text: "Helm > Engineering  Boost  waiting, 6 s left".
static func row_text(row: Dictionary) -> String:
	var time: String = time_text(row)
	return head_text(row) + ("  " + time if time != "" else "")


## A row's first line: "Helm > Engineering  Boost".
static func head_text(row: Dictionary) -> String:
	return (
		"%s > %s  %s"
		% [
			TranslationServer.translate("station." + str(row["from"])),
			TranslationServer.translate("station." + str(row["to"])),
			row["label"],
		]
	)


## A row's second line, "waiting, 6 s left", or "" once no time is left.
static func time_text(row: Dictionary) -> String:
	var left: float = float(row.get("left_s", 0.0))
	if left <= 0.0:
		return ""
	return TranslationServer.translate("captain.waiting") % ceili(left)


func show_rows(new_rows: Array[Dictionary]) -> void:
	if new_rows == rows:
		return
	rows = new_rows
	_fit()
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
		if i > 0:
			ListLines.between(
				self, Rect2(0.0, r.position.y - ROW_HEIGHT, size.x, ROW_HEIGHT - 3.0), r
			)
		draw_rect(r, Palette.color("panel"))
		var base: Vector2 = Vector2(8.0, r.position.y + 3.0 + font.get_ascent(FONT_SIZE))
		var width: float = size.x - 16.0
		draw_string(font, base, head_text(rows[i]), 0, width, FONT_SIZE, Palette.color("text"))
		base.y += font.get_descent(FONT_SIZE) + font.get_ascent(TIME_FONT_SIZE)
		var time: String = time_text(rows[i])
		draw_string(font, base, time, 0, width, TIME_FONT_SIZE, Palette.color("text_dim"))
		# The time left as a thin bar under both lines: it runs out as the request lapses.
		var share: float = clampf(
			float(rows[i].get("left_s", 0.0)) / float(rows[i].get("total_s", 1.0)), 0.0, 1.0
		)
		draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x * share, 3.0), Palette.color("warn"))
