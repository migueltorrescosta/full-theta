class_name ScienceTouchHelp
extends Control
## The touch picture of Science's phone pages for the menu's Controls tab (#28 follow-up,
## P28-Help, D292): each page drawn small as on a phone on its side (844 x 390, the rails
## as SciencePhone lays them out), every control a numbered box, and under each drawing the
## numbers with the control's name and what it does. RelayTouchHelp draws Relay's the same
## way (`draw_pages`).

## The phone the boxes are measured on, and the drawing's scale.
const PHONE: Vector2 = Vector2(844.0, 390.0)
const SCALE: float = 0.42
const FONT: int = 13
const NUMBER_FONT: int = 12
const LINE_H: float = 18.0
const GAP: float = 12.0
## The rails (design 2.4): left x 47-215, right x 629-797, rows from y 64 on a 56 px pitch.
const LEFT_X: float = 47.0
const RIGHT_X: float = 629.0
const RAIL_W: float = 168.0
const HALF_W: float = 80.0


## [{"title", "items": [[Rect2 on PHONE, name, what it does], ...]}] per page.
static func pages() -> Array:
	var r: Callable = func(col: int, row: int, wide: bool = false) -> Rect2:
		var x: float = RIGHT_X + (HALF_W + 8.0) * col
		return Rect2(x, 64.0 + 56.0 * row, RAIL_W if wide else HALF_W, 48.0)
	var list: Rect2 = Rect2(LEFT_X, 64.0, RAIL_W, 230.0)
	var actions: Array = [
		[r.call(0, 0), _t("sci.scan"), _t("intent.sci_scan")],
		[
			r.call(1, 0),
			_t("sci.hack"),
			TouchText.of("help.sci_hack", "Pick a subsystem, then hack")
		],
		[r.call(0, 1), _t("sci.ping"), _t("intent.sci_ping")],
		[r.call(1, 1), TouchText.of("sci.short_mark", "Mark"), _t("intent.sci_scan_mark")],
		[r.call(0, 2), TouchText.of("sci.short_passive", "Passive"), _t("intent.sci_mode")],
		[r.call(1, 2), TouchText.of("sci.short_self", "Own ship"), _t("intent.sci_self_scan")],
		[r.call(0, 3, true), _t("sci.claim"), _t("intent.claim")],
	]
	var crew: Array = [
		[Rect2(LEFT_X, 64.0, HALF_W, 48.0), _t("intent.request"), _t("intent.request")],
		[Rect2(LEFT_X + 88.0, 64.0, HALF_W, 48.0), _t("intent.ping"), _t("intent.ping")],
		[
			Rect2(LEFT_X, 120.0, RAIL_W, 104.0),
			_t("intent.mark"),
			TouchText.of("help.shares", "Place a mark, share data")
		],
	]
	return [
		{
			"title": TouchText.of("page.contacts", "Contacts"),
			"items":
			[[list, TouchText.of("page.contacts", "Contacts"), _t("intent.select")]] + actions,
		},
		{
			"title": TouchText.of("page.card", "Card"),
			"items":
			[
				[
					Rect2(LEFT_X, 64.0, 300.0, 280.0),
					TouchText.of("page.card", "Card"),
					TouchText.of("help.sci_card", "What the scan has found")
				]
			],
		},
		{"title": TouchText.of("page.crew", "Crew"), "items": crew},
	]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PHONE.x * SCALE, height_for(pages()))


## The height `pages` need, drawing and legend each.
static func height_for(page_list: Array) -> float:
	var h: float = 0.0
	for p: Dictionary in page_list:
		h += LINE_H + PHONE.y * SCALE + GAP + (p["items"] as Array).size() * LINE_H + GAP
	return h


func _draw() -> void:
	draw_pages(self, pages())


## Draws `page_list` into `canvas` from its top: per page the title, the small phone with
## numbered boxes, then the legend.
static func draw_pages(canvas: CanvasItem, page_list: Array) -> void:
	var font: Font = ThemeDB.fallback_font
	var y: float = 0.0
	var line: Color = Palette.color("line")
	var text: Color = Palette.color("text")
	var dim: Color = Palette.color("text_dim")
	var accent: Color = Palette.color("accent")
	for p: Dictionary in page_list:
		canvas.draw_string(
			font,
			Vector2(0.0, y + 14.0),
			str(p["title"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT + 1,
			text
		)
		y += LINE_H
		var frame: Rect2 = Rect2(Vector2(0.0, y), PHONE * SCALE)
		canvas.draw_rect(frame, Palette.color("background"))
		canvas.draw_rect(frame, line, false, 1.0)
		var items: Array = p["items"]
		for i: int in items.size():
			var box: Rect2 = items[i][0]
			var at: Rect2 = Rect2(frame.position + box.position * SCALE, box.size * SCALE)
			canvas.draw_rect(at, Palette.color("panel"))
			canvas.draw_rect(at, accent, false, 1.0)
			canvas.draw_string(
				font,
				at.position + Vector2(3.0, 13.0),
				str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				NUMBER_FONT,
				accent
			)
		y += frame.size.y + GAP
		for i: int in items.size():
			var row: String = "%d  %s: %s" % [i + 1, items[i][1], items[i][2]]
			canvas.draw_string(
				font,
				Vector2(0.0, y + 13.0),
				row,
				HORIZONTAL_ALIGNMENT_LEFT,
				PHONE.x * SCALE,
				FONT,
				dim
			)
			y += LINE_H
		y += GAP


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
