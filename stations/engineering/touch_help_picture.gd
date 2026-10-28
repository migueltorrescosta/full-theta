class_name TouchHelpPicture
extends VBoxContainer
## The touch picture of a station's phone pages for the menu's Controls tab (#28 follow-up,
## P28-Help, D292): per page, a drawing of the phone on its side with the page's tab lit and
## each control outlined with a number, then the numbered list of what each control does.
## The persistent rail shows on the first page only. A station describes its pages with a
## static `touch_help() -> Array` on its panel script:
##
##     [{"page": "Power", "boxes": [[Rect2(51, 76, 76, 48), "Power +", "One more pip"], ...]}]
##
## Boxes are in the phone frame's coordinates (FRAME, the design's 844x390 with the safe area
## x 47..797 and the top bar y 8..56).
##
##     var pic := TouchHelpPicture.make("engineering")
##     controls_tab.add_child(pic)

## The frame the boxes are drawn in.
const FRAME: Vector2 = Vector2(844.0, 390.0)
## The drawing's widest (px); narrower in a narrow menu (upright), its height follows FRAME.
const DRAW_W: float = 422.0
const NUMBER_R: float = 9.0
## Text in the drawing: never under 12 px.
const FONT: int = 12

## The pages as the station gave them.
var pages: Array = []


## The picture of `station`'s pages, or null for a station without one (Viewer).
static func make(station: String) -> TouchHelpPicture:
	var data: Array = help_of(station)
	if data.is_empty():
		return null
	var pic: TouchHelpPicture = TouchHelpPicture.new()
	pic.name = "TouchHelp_" + station
	pic.build(data)
	return pic


## A station's touch help data, [] when it has none.
static func help_of(station: String) -> Array:
	match station:
		"engineering":
			return EngineeringPanel.touch_help()
		"comms":
			return _of(load("res://stations/comms/comms_panel.gd"))
		"captain":
			return _of(load("res://stations/captain/captain_panel.gd"))
	return []


static func _of(script: Script) -> Array:
	if script == null or not script.has_method("touch_help"):
		return []
	return script.call("touch_help")


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)


## Builds one section per page, numbering the controls across pages.
func build(data: Array) -> void:
	pages = data
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var titles: Array[String] = []
	for p: Dictionary in data:
		titles.append(str(p["page"]))
	var n: int = 1
	for i: int in data.size():
		var page: Dictionary = data[i]
		var head: Label = Label.new()
		head.text = titles[i]
		head.add_theme_color_override("font_color", Palette.color("accent"))
		add_child(head)
		var draw: PageDrawing = PageDrawing.new()
		draw.titles = titles
		draw.current = i
		draw.boxes = page["boxes"]
		draw.first = n
		add_child(draw)
		var legend: GridContainer = GridContainer.new()
		legend.columns = 2
		legend.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
		add_child(legend)
		for b: Array in page["boxes"]:
			var num: Label = Label.new()
			num.text = str(n)
			num.add_theme_color_override("font_color", Palette.color("accent"))
			legend.add_child(num)
			var what: Label = Label.new()
			what.text = "%s: %s" % [str(b[1]), str(b[2])]
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			legend.add_child(what)
			n += 1


## The numbers of the controls in the order the list shows them.
func count() -> int:
	var n: int = 0
	for p: Dictionary in pages:
		n += (p["boxes"] as Array).size()
	return n


## One page's drawing: the phone outline, the top bar with the page tabs, the boxes.
class PageDrawing:
	extends Control

	var titles: Array[String] = []
	var current: int = 0
	var boxes: Array = []
	## The number of the first box.
	var first: int = 1

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, DRAW_W * FRAME.y / FRAME.x)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Pixels per frame pixel: DRAW_W wide at most, the width it gets in a narrow menu.
	func scale_k() -> float:
		return minf(size.x, DRAW_W) / FRAME.x

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
		# The top bar: the page tabs from x 251, 64 px each with 8 px gaps (design 1.2).
		for i: int in titles.size():
			var r: Rect2 = Rect2(Vector2(251.0 + i * 72.0, 10.0), Vector2(64.0, 44.0))
			var on: bool = i == current
			var col: Color = Palette.color("accent" if on else "line")
			draw_rect(_scaled(r, k), col, on, -1.0 if on else 1.0)
			draw_string(
				font,
				_scaled(r, k).position + Vector2(3.0, r.size.y * k * 0.65),
				titles[i],
				HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x * k - 6.0,
				FONT,
				Palette.color("background" if on else "text")
			)
		for j: int in boxes.size():
			var b: Array = boxes[j]
			var r: Rect2 = _scaled(b[0], k)
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
			# The control's name beside its number, when the box has room.
			var room: float = r.size.x - 2.0 * NUMBER_R - 8.0
			if room >= 24.0:
				draw_string(
					font,
					Vector2(c.x + NUMBER_R + 4.0, c.y + 4.5),
					str(b[1]),
					HORIZONTAL_ALIGNMENT_LEFT,
					room,
					FONT,
					Palette.color("text")
				)

	static func _scaled(r: Rect2, k: float) -> Rect2:
		return Rect2(r.position * k, r.size * k)
