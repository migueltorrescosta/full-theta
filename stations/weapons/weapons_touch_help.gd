class_name WeaponsTouchHelp
extends Control
## The touch help picture of Weapons' phone pages (#28 follow-up, P28-Help, D292): each page
## (Fire, Mounts, Crew) drawn as a small phone on its side with numbered callouts on its
## controls, and beside it what each number does. The boxes follow WeaponsTouch's layout on
## the mockups' 844 x 390 phone (one right rail over a full-width view). Meant for the menu's
## Controls tab on a touch device; it sizes itself to its contents.

## The reference phone (px) the boxes are given in, and the drawing's scale.
const PHONE: Vector2 = Vector2(844.0, 390.0)
const SCALE: float = 0.42
const FONT: int = 13
const ROW_GAP: float = 16.0
const BADGE_R: float = 9.0
## Each page: [title key, English, [[rect in PHONE px, key, English], ...]].
const PAGES: Array = [
	[
		"page.fire",
		"Fire",
		[
			[Rect2(629, 64, 168, 64), "help.weapons.mount", "Mount card: tap for the next mount"],
			[Rect2(629, 136, 80, 48), "help.weapons.ammo", "Ammo: the next ammunition"],
			[Rect2(717, 136, 80, 48), "help.weapons.guided", "Guided: fire at the selected mark"],
			[Rect2(629, 192, 80, 48), "help.weapons.fire_all", "Fire all: hold, every mount fires"],
			[Rect2(717, 192, 80, 48), "help.weapons.claim", "Claim or Release this mount"],
			[Rect2(629, 262, 168, 104), "help.weapons.fire", "FIRE: hold to fire"],
			[
				Rect2(240, 150, 360, 150),
				"help.weapons.view",
				"View: drag to aim, tap to select, hold to ping"
			],
			[Rect2(55, 232, 160, 126), "help.weapons.radar", "Radar: tap a blip to select it"],
			[Rect2(192, 64, 284, 48), "help.weapons.chip", "Target: ‹ › next, tap for more"],
		],
	],
	[
		"page.mounts",
		"Mounts",
		[
			[Rect2(223, 128, 294, 56), "help.weapons.row", "Mount: tap to look through it"],
			[Rect2(525, 128, 88, 56), "help.weapons.row_claim", "Claim or release that mount"],
			[Rect2(629, 262, 168, 104), "help.weapons.fire", "FIRE: hold to fire"],
		],
	],
	[
		"page.crew",
		"Crew",
		[
			[Rect2(629, 64, 168, 64), "help.weapons.requests", "Ask for power or a turn"],
			[Rect2(629, 136, 168, 48), "help.weapons.ping_mark", "Ping or mark the target"],
			[Rect2(629, 192, 168, 48), "help.weapons.share", "Share what you see"],
			[Rect2(629, 262, 168, 104), "help.weapons.fire", "FIRE: hold to fire"],
		],
	],
]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		PHONE.x * SCALE * 2.0 + ROW_GAP, PAGES.size() * (PHONE.y * SCALE + ROW_GAP)
	)


## The callouts of page `i`: [rect (reference px), text], numbered from 1.
static func callouts(i: int) -> Array:
	var out: Array = []
	for c: Array in PAGES[i][2]:
		out.append([c[0], TouchText.of(c[1], c[2])])
	return out


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var line: Color = Palette.color("text_dim")
	var text: Color = Palette.color("text")
	var accent: Color = Palette.color("accent")
	var h: float = PHONE.y * SCALE
	for i: int in PAGES.size():
		var o: Vector2 = Vector2(0.0, i * (h + ROW_GAP))
		var phone: Rect2 = Rect2(o, PHONE * SCALE)
		draw_rect(phone, Palette.color("panel"))
		draw_rect(phone, line, false, 1.0)
		# The top bar with the page tabs, the current one filled.
		draw_line(o + Vector2(0, 56) * SCALE, o + Vector2(PHONE.x, 56) * SCALE, line, 1.0)
		for t: int in PAGES.size():
			var tab: Rect2 = Rect2(o + Vector2(251 + t * 72, 10) * SCALE, Vector2(64, 44) * SCALE)
			draw_rect(tab, accent if t == i else line, t == i, 1.0)
		var title: String = TouchText.of(PAGES[i][0], PAGES[i][1])
		draw_string(font, o + Vector2(8, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, text)
		# The rail.
		var rail: Rect2 = Rect2(o + Vector2(629, 56) * SCALE, Vector2(168, 310) * SCALE)
		draw_rect(rail, Color(line, 0.15))
		var calls: Array = callouts(i)
		var lx: float = phone.end.x + ROW_GAP
		for k: int in calls.size():
			var r: Rect2 = calls[k][0]
			var box: Rect2 = Rect2(o + r.position * SCALE, r.size * SCALE)
			draw_rect(box, accent, false, 1.5)
			var badge: Vector2 = box.position + Vector2(BADGE_R, BADGE_R)
			draw_circle(badge, BADGE_R, accent)
			var n: String = str(k + 1)
			draw_string(
				font,
				badge + Vector2(-BADGE_R, FONT / 2.0 - 2.0),
				n,
				HORIZONTAL_ALIGNMENT_CENTER,
				BADGE_R * 2.0,
				FONT - 1,
				Palette.color("background")
			)
			var y: float = o.y + FONT + 2.0 + k * (FONT + 5.0)
			draw_string(
				font,
				Vector2(lx, y),
				"%d  %s" % [k + 1, calls[k][1]],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				FONT,
				text
			)
