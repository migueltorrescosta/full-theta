class_name TouchHelpPicture
extends VBoxContainer
## The touch picture of a station's phone pages for the menu's Controls tab (#28 follow-up,
## P28-Help, D292): per page, a drawing of the phone on its side with the page's tab lit and
## each control outlined with a number, then the numbered list of what each control does.
## The persistent rail shows on the first page only. A station describes its pages with a
## static `touch_help() -> Array[HelpPage]` on its panel script:
##
##     [HelpPage.new("Power", [HelpBox.new(Rect2(51, 76, 76, 48), "Power +", "One more pip")])]
##
## Boxes are in the phone frame's coordinates (FRAME, the design's 844x390 with the safe area
## x 47..797 and the top bar y 8..56).
##
##     var pic := TouchHelpPicture.make("engineering")
##     controls_tab.add_child(pic)
##
## help_of names each station's script with a `touch_help()` (the panel; Weapons' phone).
## Its texts are translations of keys of content/i18n/strings.json.

## The frame the boxes are drawn in.
const FRAME: Vector2 = Vector2(844.0, 390.0)
## The drawing's widest (px); narrower in a narrow menu (upright), its height follows FRAME.
const DRAW_WIDTH: float = 422.0
const NUMBER_R: float = 9.0
## Text in the drawing: never under 12 px.
const FONT: int = 12

## The stations with a `touch_help()` (help_of's arms, in its order; ControlsHoldHelp's
## first-wins order); the others show no picture.
const STATIONS: Array[String] = [
	"engineering", "comms", "captain", "helm", "weapons", "science", "relay"
]

## The pages as the station gave them.
var pages: Array[HelpPage] = []


## The picture of `station`'s pages, or null for a station without one (Viewer).
static func make(station: String) -> TouchHelpPicture:
	var data: Array[HelpPage] = help_of(station)
	if data.is_empty():
		return null
	var pic: TouchHelpPicture = TouchHelpPicture.new()
	pic.name = "TouchHelp_" + station
	pic.build(data)
	return pic


## A station's touch help pages, [] when it has none.
static func help_of(station: String) -> Array[HelpPage]:
	match station:
		"engineering":
			return EngineeringPanel.touch_help()
		"comms":
			return CommsPanel.touch_help()
		"captain":
			return CaptainPanel.touch_help()
		"helm":
			return HelmPanel.touch_help()
		"weapons":
			return WeaponsTouch.touch_help()
		"science":
			return SciencePanel.touch_help()
		"relay":
			return RelayPanel.touch_help()
	return []


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)


## Builds one section per page, numbering the controls across pages.
func build(data: Array[HelpPage]) -> void:
	pages = data
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var titles: Array[String] = []
	for p: HelpPage in data:
		titles.append(p.title)
	var n: int = 1
	for i: int in data.size():
		var page: HelpPage = data[i]
		var head: Label = Label.new()
		head.text = titles[i]
		head.add_theme_color_override("font_color", Palette.color("accent"))
		add_child(head)
		var draw: PageDrawing = PageDrawing.new()
		draw.titles = titles
		draw.current = i
		draw.boxes = page.boxes
		draw.first = n
		add_child(draw)
		var legend: GridContainer = GridContainer.new()
		legend.columns = 2
		legend.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
		add_child(legend)
		for b: HelpBox in page.boxes:
			var num: Label = Label.new()
			num.text = str(n)
			num.add_theme_color_override("font_color", Palette.color("accent"))
			legend.add_child(num)
			var what: Label = Label.new()
			# (a bare name when the station gives no more: "All stop")
			what.text = b.label if b.what == b.label else "%s: %s" % [b.label, b.what]
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			legend.add_child(what)
			n += 1


## The numbers of the controls in the order the list shows them.
func count() -> int:
	var n: int = 0
	for p: HelpPage in pages:
		n += p.boxes.size()
	return n


## One page's drawing: the phone outline, the top bar with the page tabs, the boxes.
class PageDrawing:
	extends Control

	var titles: Array[String] = []
	var current: int = 0
	var boxes: Array[HelpBox] = []
	## The number of the first box.
	var first: int = 1

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, DRAW_WIDTH * FRAME.y / FRAME.x)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Pixels per frame pixel: DRAW_WIDTH wide at most, the width it gets in a narrow menu.
	func scale_k() -> float:
		return minf(size.x, DRAW_WIDTH) / FRAME.x

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			var h: float = scale_k() * FRAME.y
			if size.x > 0.0 and not is_equal_approx(custom_minimum_size.y, h):
				custom_minimum_size.y = h
			queue_redraw()

	func _draw() -> void:
		var k: float = scale_k()
		var font: Font = get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, FRAME * k), Palette.color("background"))
		draw_rect(Rect2(Vector2.ZERO, FRAME * k), Palette.color("line"), false, 2.0)
		# The top bar: the page tabs from x 251, 8 px apart, each at least 64 px and, in the
		# drawing, as wide as its 12 px label (PageTabs, design 1.2).
		var x: float = 251.0 * k
		for i: int in titles.size():
			var label_width: float = (
				font.get_string_size(titles[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
			)
			var r: Rect2 = Rect2(x, 10.0 * k, maxf(64.0 * k, label_width + 6.0), 44.0 * k)
			x = r.end.x + 8.0 * k
			var on: bool = i == current
			var col: Color = Palette.color("accent" if on else "line")
			draw_rect(r, col, on, -1.0 if on else 1.0)
			draw_string(
				font,
				r.position + Vector2(3.0, r.size.y * 0.5 + 4.5),
				titles[i],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				FONT,
				Palette.color("background" if on else "text")
			)
		for j: int in boxes.size():
			var b: HelpBox = boxes[j]
			var r: Rect2 = _scaled(b.box, k)
			draw_rect(r, Palette.color("panel"))
			draw_rect(r, Palette.color("text_dim"), false, 1.0)
			var c: Vector2 = r.position + Vector2(NUMBER_R + 2.0, NUMBER_R + 2.0)
			draw_circle(c, NUMBER_R, Palette.color("accent"))
			var num: String = str(first + j)
			var w: float = font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
			draw_string(
				font,
				c + Vector2(-w / 2.0, 4.5),
				num,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				FONT,
				Palette.color("background")
			)
			# The control's name beside its number when it fits whole (else the number alone).
			var room: float = r.size.x - 2.0 * NUMBER_R - 8.0
			var name_width: float = (
				font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
			)
			if name_width <= room:
				draw_string(
					font,
					Vector2(c.x + NUMBER_R + 4.0, c.y + 4.5),
					b.label,
					HORIZONTAL_ALIGNMENT_LEFT,
					room,
					FONT,
					Palette.color("text")
				)

	static func _scaled(r: Rect2, k: float) -> Rect2:
		return Rect2(r.position * k, r.size * k)
