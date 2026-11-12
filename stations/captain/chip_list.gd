class_name ChipList
extends Control
## The Captain's read-only list of open request chips (FT-CPT-004): each row reads
## "Helm > Engineering  Boost", then "waiting, 6 s left" over a bar that runs out with it
## (R23-12). A request that goes stays DONE_MS as "Answered", or "Expired" when it ran out
## (ChipLapse's rule), then its row goes. It reads the CHIPS block through ChipsReader
## (`open_rows`) and answers no input.
##
## A row: {"id": chip id, "from": station id, "to": station id, "label": text, "left_s":
## seconds left, "total_s": its whole time}; a gone one also has "state" (answered, expired)
## and "until" (ms).

const DONE_MS: int = 3000
const ROW_HEIGHT: float = 50.0
## The rows keep this much clear of the list's right edge.
const MARGIN: float = 8.0
const TIME_FONT_SIZE: int = 13
const HEADER_HEIGHT: float = 26.0
const FONT_SIZE: int = 15
const MAX_ROWS: int = 6

var rows: Array[Dictionary] = []
## The requests that went, newest last, while they show their state.
var done: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()


## The height of the rows shown (at least one), so a short list leaves the panel unscrolled.
func _fit() -> void:
	var n: int = clampi(rows.size() + done.size(), 1, MAX_ROWS)
	custom_minimum_size = Vector2(0, HEADER_HEIGHT + ROW_HEIGHT * n)


## Rows of the view's CHIPS block: all of the ship's open chips (the Captain sees them
## all), with the text in the session language and the seconds left.
static func open_rows(snap: SnapshotState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chip: Dictionary in ChipsReader.open_chips(snap):
		var callsign: String = snap.callsign(int(chip["arg"])) if int(chip["arg"]) >= 0 else ""
		(
			out
			. append(
				{
					"id": int(chip["id"]),
					"from": chip["from"],
					"to": chip["to"],
					"label": ChipsReader.label(chip, callsign),
					"left_s": ChipsReader.left_s(snap, chip),
					"total_s":
					maxf(float(int(chip["expires"]) - int(chip["sent"])) / ChipsReader.HZ, 1.0),
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


## A row's second line, "waiting, 6 s left", or "" once no time is left; a gone request's
## state ("Answered", "Expired").
static func time_text(row: Dictionary) -> String:
	if row.has("state"):
		return TranslationServer.translate("captain.chip_" + str(row["state"]))
	var left: float = float(row.get("left_s", 0.0))
	if left <= 0.0:
		return ""
	return TranslationServer.translate("captain.waiting") % ceili(left)


## Shows the open requests at `now_ms` (the wall clock by default): a request gone since the
## last call shows its state for DONE_MS.
func show_rows(new_rows: Array[Dictionary], now_ms: int = -1) -> void:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var open: Dictionary = {}
	for r: Dictionary in new_rows:
		open[r.get("id", -1)] = true
	var kept: Array[Dictionary] = done.filter(func(d: Dictionary) -> bool: return now < d["until"])
	for r: Dictionary in rows:
		if not open.has(r.get("id", -1)):
			var gone: Dictionary = r.duplicate()
			var lapsed: bool = ChipLapse.lapsed(float(r.get("left_s", 0.0)))
			gone["state"] = "expired" if lapsed else "answered"
			gone["until"] = now + DONE_MS
			kept.append(gone)
	if new_rows == rows and kept == done:
		return
	rows = new_rows
	done = kept
	_fit()
	queue_redraw()


## Every row drawn: the open ones, then the gone ones.
func shown() -> Array[Dictionary]:
	return rows + done


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
	var all: Array[Dictionary] = shown()
	if all.is_empty():
		var none: String = TranslationServer.translate("captain.no_chips")
		var base: Vector2 = Vector2(8.0, HEADER_HEIGHT + font.get_ascent(FONT_SIZE) + 4.0)
		draw_string(font, base, none, 0, size.x - 16.0, FONT_SIZE, Palette.color("text_dim"))
		return
	for i: int in mini(all.size(), MAX_ROWS):
		var row: Dictionary = all[i]
		var gone: bool = row.has("state")
		var w: float = size.x - MARGIN
		var r: Rect2 = Rect2(0.0, HEADER_HEIGHT + i * ROW_HEIGHT, w, ROW_HEIGHT - 3.0)
		if i > 0:
			ListLines.between(self, Rect2(0.0, r.position.y - ROW_HEIGHT, w, ROW_HEIGHT - 3.0), r)
		draw_rect(r, Palette.color("panel"))
		var base: Vector2 = Vector2(8.0, r.position.y + 3.0 + font.get_ascent(FONT_SIZE))
		var width: float = w - 16.0
		var head: Color = Palette.color("text_dim" if gone else "text")
		draw_string(font, base, head_text(row), 0, width, FONT_SIZE, head)
		base.y += font.get_descent(FONT_SIZE) + font.get_ascent(TIME_FONT_SIZE)
		var role: String = "text_dim"
		if gone:
			role = "warn" if row["state"] == "expired" else "accent"
		draw_string(font, base, time_text(row), 0, width, TIME_FONT_SIZE, Palette.color(role))
		if gone:
			continue
		# The time left as a thin bar under both lines: it runs out as the request lapses.
		var share: float = clampf(
			float(row.get("left_s", 0.0)) / float(row.get("total_s", 1.0)), 0.0, 1.0
		)
		draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x * share, 3.0), Palette.color("warn"))
