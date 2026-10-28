class_name HelmHelp
extends Control
## Helm's touch help picture for the menu's Controls tab (#28 follow-up, P28-Help): each
## phone page (HelmTouch's pages, on its side) as a small drawing with numbered callouts,
## and under it what each number does. The Fly page also numbers the persistent controls,
## the page tabs, the selection chip and the long-press; the other pages only what they
## add. Drawn from the design's geometry (design 2.1, 844 x 390), not from a live layout,
## so it costs nothing until the menu shows it.

## The phone's size the geometry is in, and the drawing's width.
const PHONE: Vector2 = Vector2(844.0, 390.0)
const WIDTH: float = 340.0
const FONT: int = 13
const BADGE_R: float = 9.0
const LINE_H: float = 20.0
const GAP: float = 12.0
## Helm's help texts until content/i18n/strings.json has their "touch.helm.help.*" keys.
const TEXTS: Dictionary = {
	"throttle": "Throttle: drag to set your speed",
	"turn": "Turn stick: point the nose",
	"slide": "Slide stick: move sideways, up and down",
	"tabs": "Pages: tap to switch",
	"chip": "Target: ‹ › next; tap the name to ping or mark",
	"hold": "Hold the view to ping; hold and drag to mark",
	"glyph": "Shield ring: where the shields point",
	"ring": "Shield ring: tap where the shields go",
	"radar": "Radar: tap a blip to select it",
	"range": "Range − and +: zoom the radar",
	"crew": "Requests, Ping, Mark and Share",
}
## Callouts: [key, box in PHONE px, round]. A key with a HelmTouch button is the intent
## (its label is the intent's); others are TEXTS keys.
const PERSISTENT: Array = [
	["throttle", Rect2(51, 64, 48, 294), false],
	["all_stop", Rect2(107, 64, 108, 48), false],
	["approach", Rect2(107, 120, 108, 48), false],
	["turn", Rect2(107, 242, 108, 108), true],
	["slide", Rect2(659, 242, 108, 108), true],
	["tabs", Rect2(251, 10, 352, 44), false],
	["chip", Rect2(280, 64, 284, 44), false],
	["hold", Rect2(380, 180, 80, 80), true],
]
const PAGES: Array = [
	[
		["face", Rect2(629, 64, 80, 48), false],
		["align", Rect2(717, 64, 80, 48), false],
		["shield_track", Rect2(629, 120, 80, 48), false],
		["glyph", Rect2(683, 176, 60, 60), true],
	],
	[["ring", Rect2(638, 64, 150, 150), true]],
	[
		["dock", Rect2(629, 64, 80, 48), false],
		["jump", Rect2(717, 64, 80, 48), false],
		["chase_camera", Rect2(629, 120, 80, 48), false],
		["decoupled", Rect2(717, 120, 80, 48), false],
	],
	[
		["range", Rect2(629, 64, 168, 48), false],
		["radar", Rect2(231, 116, 382, 242), false],
	],
	[["crew", Rect2(629, 64, 168, 160), false]],
]

## [page title, [[number, key, box, round], ...]] for each picture, numbered across pages.
var pictures: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n: int = 1
	var titles: Array[String] = HelmTouch.page_titles()
	for p: int in PAGES.size():
		var calls: Array = []
		for c: Array in (PERSISTENT if p == HelmTouch.PAGE_FLY else []) + PAGES[p]:
			calls.append([n, c[0], c[1], c[2]])
			n += 1
		pictures.append([titles[p], calls])
	custom_minimum_size = Vector2(WIDTH, _height())


## What callout `key` says: an intent's label, else a help text.
static func text(key: String) -> String:
	if TEXTS.has(key):
		return TouchText.of("touch.helm.help." + key, TEXTS[key])
	return TranslationServer.translate(IntentTable.label_key(key))


func _scale() -> float:
	return WIDTH / PHONE.x


func _picture_h(calls: Array) -> float:
	return LINE_H + PHONE.y * _scale() + 4.0 + calls.size() * LINE_H + GAP


func _height() -> float:
	var h: float = 0.0
	for pic: Array in pictures:
		h += _picture_h(pic[1])
	return h


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var k: float = _scale()
	var dim: Color = Palette.color("text_dim")
	var text_col: Color = Palette.color("text")
	var y: float = 0.0
	for p: int in pictures.size():
		var pic: Array = pictures[p]
		draw_string(font, Vector2(0.0, y + FONT + 2.0), str(pic[0]), 0, -1, FONT + 1, text_col)
		y += LINE_H
		var phone: Rect2 = Rect2(Vector2(0.0, y), PHONE * k)
		_phone(phone, p)
		for c: Array in pic[1]:
			var box: Rect2 = _box(phone, c[2])
			_shape(box, c[3], dim)
			_badge(font, box.position, int(c[0]))
		y += phone.size.y + 4.0
		for c: Array in pic[1]:
			_badge(font, Vector2(0.0, y + LINE_H / 2.0 - BADGE_R), int(c[0]))
			var at: Vector2 = Vector2(2.0 * BADGE_R + 6.0, y + FONT + 2.0)
			draw_string(font, at, text(c[1]), 0, WIDTH - at.x, FONT, text_col)
			y += LINE_H
		y += GAP


## The phone of page `page`: the frame, both rails, the page tabs with `page`'s lit, and on
## pages after the first the persistent controls without numbers.
func _phone(phone: Rect2, page: int) -> void:
	var line: Color = Palette.color("line")
	draw_rect(phone, Color(Palette.color("background"), 0.9))
	draw_rect(phone, line, false, 1.0)
	for rail: Rect2 in [Rect2(47, 64, 168, 294), Rect2(629, 64, 168, 294)]:
		draw_rect(_box(phone, rail), Palette.color("panel"))
	for i: int in PAGES.size():
		var tab: Rect2 = _box(phone, Rect2(251.0 + 72.0 * i, 10.0, 64.0, 44.0))
		if i == page:
			draw_rect(tab, Palette.color("accent"))
		else:
			draw_rect(tab, line, false, 1.0)
	if page != HelmTouch.PAGE_FLY:
		for c: Array in PERSISTENT:
			if c[0] not in ["tabs", "hold"]:
				_shape(_box(phone, c[1]), c[2], line)


func _box(phone: Rect2, r: Rect2) -> Rect2:
	var k: float = _scale()
	return Rect2(phone.position + r.position * k, r.size * k)


func _shape(box: Rect2, round: bool, col: Color) -> void:
	if round:
		draw_arc(box.get_center(), minf(box.size.x, box.size.y) / 2.0, 0.0, TAU, 32, col, 1.5)
	else:
		draw_rect(box, col, false, 1.5)


## A numbered disc whose top-left is near `at`.
func _badge(font: Font, at: Vector2, n: int) -> void:
	var c: Vector2 = at + Vector2(BADGE_R, BADGE_R)
	draw_circle(c, BADGE_R, Palette.color("accent"))
	var label: String = str(n)
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1).x
	draw_string(
		font,
		c + Vector2(-w / 2.0, (FONT - 1) * 0.35),
		label,
		0,
		-1,
		FONT - 1,
		Palette.color("background")
	)
