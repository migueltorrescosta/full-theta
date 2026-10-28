class_name UiTheme
extends RefCounted
## The one generic modern theme of every client, desktop and browser (D194): a Godot
## Theme built from Palette tokens, so the colour-blind checks of tools/check_palette.py
## cover it (FT-STN-006). Applied once at the root window (`apply`); screens style by
## type variation, not by hand. The UI scale (FT-STN-013, 75-150 %) is the window's
## content scale, so every size here is at 100 %.
##
## Variations (set `theme_type_variation`):
## - Label: TitleLabel, HeadingLabel, SmallLabel, DimLabel, CaptionLabel (small and dim),
##   CrewLabel (small, normal text colour: the seat holders' names, D257).
## - Button: TouchButton, OptionButton: TouchOptionButton, CheckBox: TouchCheckBox -
##   targets at least TOUCH_MIN px tall at 100 %, for the touch layouts.
## - Button: LoadCell_intense, LoadCell_busy, LoadCell_light, LoadCell_none - the lobby's
##   station cells, bordered in the load colour.
## - Button: RailButton, RailAccentButton, RailDangerButton - the thumb rails' primary
##   targets (presentation/touch/, #28): narrow side padding, an accent or danger border.
## - PanelContainer: OverlayRail (translucent, over a view), DockedRail (opaque), Drawer,
##   Banner.
##
## Touch sizes (#28, amends D218): primary targets at least TOUCH_PRIMARY px with TOUCH_GAP
## px between them; nothing tappable under TOUCH_MIN px.

## The smallest touch target, in px at 100 % UI scale.
const TOUCH_MIN: int = 44
## The smallest primary touch target (rail buttons, sticks, the throttle).
const TOUCH_PRIMARY: int = 48
## The least gap between two touch targets.
const TOUCH_GAP: int = 8
## How opaque an overlay rail's panel is over the view.
const OVERLAY_ALPHA: float = 0.72
const FONT_SIZE: int = 16
const TITLE_SIZE: int = 32
const HEADING_SIZE: int = 20
const SMALL_SIZE: int = 12
const RADIUS: int = 8
const BORDER: int = 1
## The focus ring's width.
const RING: int = 2
const SPACING: int = 8
## An embedded dialog's title bar and the frame around the rest of it (px).
const WINDOW_TITLE_H: float = 36.0
const WINDOW_MARGIN: float = 8.0
## A CheckBox's box (px).
const CHECK_ICON: int = 18
## Vertical content margin of a touch control: with the font's line height it reaches
## TOUCH_MIN.
const TOUCH_PAD: int = 12
const CELL_PAD: int = 8
const LOAD_VARIANTS: Array[String] = ["intense", "busy", "light", "none"]


## A fresh theme. The result is a plain resource; `apply` puts it on a window. With
## `touch` every plain button, option button, check box and text field is tap-sized (the
## touch and phone layouts of LayoutMode, FT-STN-005); the Touch* variations are tap-sized
## either way.
static func build(touch: bool = false) -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = FONT_SIZE
	_labels(t)
	_buttons(t, "Button", "", 16 if touch else 8, TOUCH_PAD if touch else 4)
	_buttons(t, "Button", "TouchButton", 16, TOUCH_PAD)
	_buttons(t, "OptionButton", "", 16 if touch else 8, TOUCH_PAD if touch else 4)
	_buttons(t, "OptionButton", "TouchOptionButton", 16, TOUCH_PAD)
	_check(t, "CheckBox", "", TOUCH_PAD if touch else 4)
	_check(t, "CheckBox", "TouchCheckBox", TOUCH_PAD)
	for tag: String in LOAD_VARIANTS:
		_cell(t, tag)
	_rails(t)
	_panels(t)
	_fields(t, TOUCH_PAD if touch else 6)
	if touch:
		# A list row is a tap target too.
		t.set_constant("v_separation", "ItemList", 18)
	_popups(t)
	t.set_constant("separation", "VBoxContainer", SPACING)
	t.set_constant("separation", "HBoxContainer", SPACING)
	t.set_constant("h_separation", "GridContainer", SPACING)
	t.set_constant("v_separation", "GridContainer", SPACING)
	return t


## A rounded box in the palette: fill and border roles, a content margin on each side.
static func box(fill: String, line: String, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Palette.color(fill)
	s.set_corner_radius_all(RADIUS)
	if line != "":
		s.border_color = Palette.color(line)
		s.set_border_width_all(BORDER)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## The focus ring: an outline in the accent colour with no fill.
static func ring(pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = box("accent", "accent", pad_x, pad_y)
	s.draw_center = false
	s.set_border_width_all(RING)
	return s


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", Palette.color("text"))
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", TITLE_SIZE)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_font_size("font_size", "HeadingLabel", HEADING_SIZE)
	t.set_type_variation("SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", SMALL_SIZE)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", Palette.color("text_dim"))
	t.set_type_variation("CaptionLabel", "SmallLabel")
	t.set_color("font_color", "CaptionLabel", Palette.color("text_dim"))
	t.set_type_variation("CrewLabel", "SmallLabel")
	t.set_color("font_color", "CrewLabel", Palette.color("text"))


## The four button states and the focus ring of a Button-like type.
static func _buttons(t: Theme, type: String, variation: String, pad_x: int, pad_y: int) -> void:
	var name: String = type if variation == "" else variation
	if variation != "":
		t.set_type_variation(variation, type)
	t.set_stylebox("normal", name, box("panel", "line", pad_x, pad_y))
	t.set_stylebox("hover", name, box("panel_focus", "accent", pad_x, pad_y))
	t.set_stylebox("pressed", name, box("panel_focus", "accent", pad_x, pad_y))
	t.set_stylebox("hover_pressed", name, box("panel_focus", "accent", pad_x, pad_y))
	t.set_stylebox("disabled", name, box("background", "line", pad_x, pad_y))
	t.set_stylebox("focus", name, ring(pad_x, pad_y))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, name, Palette.color("text"))
	t.set_color("font_hover_pressed_color", name, Palette.color("text"))
	t.set_color("font_disabled_color", name, Palette.color("text_dim"))


static func _check(t: Theme, type: String, variation: String, pad_y: int) -> void:
	var name: String = type if variation == "" else variation
	if variation != "":
		t.set_type_variation(variation, type)
	var plain: StyleBoxFlat = StyleBoxFlat.new()
	plain.draw_center = false
	plain.content_margin_top = pad_y
	plain.content_margin_bottom = pad_y
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, name, plain)
	t.set_stylebox("focus", name, ring(4, pad_y))
	t.set_color("font_color", name, Palette.color("text"))
	t.set_color("font_disabled_color", name, Palette.color("text_dim"))
	# Godot's grey box hardly shows on the panels: a box in the text colour, filled with
	# the accent and ticked when on (#28: a checkbox reads at 3:1 or more).
	t.set_icon("unchecked", name, check_icon(false, "text"))
	t.set_icon("checked", name, check_icon(true, "text"))
	t.set_icon("unchecked_disabled", name, check_icon(false, "line"))
	t.set_icon("checked_disabled", name, check_icon(true, "line"))


## A CheckBox icon: a CHECK_ICON px box with a 2 px border in `edge`; `on` fills it with
## the accent and draws a tick in the background colour.
static func check_icon(on: bool, edge: String) -> ImageTexture:
	var n: int = CHECK_ICON
	var img: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var tick: Array[Vector2] = [Vector2(0.25, 0.52), Vector2(0.43, 0.7), Vector2(0.76, 0.32)]
	for y: int in n:
		for x: int in n:
			var border: bool = mini(mini(x, y), mini(n - 1 - x, n - 1 - y)) < 2
			var c: Color = Color(0, 0, 0, 0)
			if border:
				c = Palette.color(edge)
			elif on:
				c = Palette.color("accent")
				var p: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / float(n)
				for i: int in 2:
					var q: Vector2 = Geometry2D.get_closest_point_to_segment(
						p, tick[i], tick[i + 1]
					)
					if p.distance_to(q) * n < 1.6:
						c = Palette.color("background")
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A lobby station cell: a toggle button with a thick border in a load colour; the
## chosen cell is filled, a disabled one fades.
static func _cell(t: Theme, tag: String) -> void:
	var name: String = "LoadCell_" + tag
	t.set_type_variation(name, "Button")
	var line: String = "load_" + tag if tag != "none" else "line"
	var normal: StyleBoxFlat = box("panel", line, CELL_PAD, CELL_PAD)
	normal.set_border_width_all(2)
	var chosen: StyleBoxFlat = box("panel_focus", line, CELL_PAD, CELL_PAD)
	chosen.set_border_width_all(4)
	var off: StyleBoxFlat = box("background", "line", CELL_PAD, CELL_PAD)
	# Hover: the chosen fill with a mid-width border, so it differs from a picked cell.
	var hover: StyleBoxFlat = box("panel_focus", line, CELL_PAD, CELL_PAD)
	hover.set_border_width_all(3)
	t.set_stylebox("normal", name, normal)
	t.set_stylebox("hover", name, hover)
	t.set_stylebox("pressed", name, chosen)
	t.set_stylebox("hover_pressed", name, chosen)
	t.set_stylebox("disabled", name, off)
	t.set_stylebox("focus", name, ring(CELL_PAD, CELL_PAD))
	t.set_color("font_disabled_color", name, Palette.color("text_dim"))


## The rail buttons and the rail, drawer and banner panels (presentation/touch/).
static func _rails(t: Theme) -> void:
	_buttons(t, "Button", "RailButton", 6, TOUCH_PAD)
	for role: String in ["accent", "danger"]:
		var name: String = "Rail%sButton" % role.capitalize()
		_buttons(t, "Button", name, 6, TOUCH_PAD)
		var fill: Color = Palette.color("panel_focus")
		if role == "danger":
			fill = Palette.color("danger").darkened(0.55)
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var s: StyleBoxFlat = box("panel_focus", role, 6, TOUCH_PAD)
			s.bg_color = fill.lightened(0.12) if state != "normal" else fill
			s.set_border_width_all(RING)
			t.set_stylebox(state, name, s)
	var overlay: StyleBoxFlat = box("panel", "", 4, 4)
	overlay.bg_color = Color(Palette.color("panel"), OVERLAY_ALPHA)
	t.set_type_variation("OverlayRail", "PanelContainer")
	t.set_stylebox("panel", "OverlayRail", overlay)
	t.set_type_variation("DockedRail", "PanelContainer")
	t.set_stylebox("panel", "DockedRail", box("panel", "", 4, 4))
	t.set_type_variation("Drawer", "PanelContainer")
	t.set_stylebox("panel", "Drawer", box("panel", "line", 8, 8))
	t.set_type_variation("Banner", "PanelContainer")
	t.set_stylebox("panel", "Banner", box("panel_focus", "accent", 12, 2))


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", box("panel", "line", 12, 12))
	t.set_stylebox("panel", "Panel", box("panel", "line", 0, 0))
	t.set_stylebox("panel", "PopupPanel", box("panel", "line", 12, 12))
	t.set_stylebox("panel", "TabContainer", box("panel", "line", 8, 8))
	t.set_stylebox("tab_selected", "TabContainer", box("panel_focus", "accent", 12, 6))
	t.set_stylebox("tab_unselected", "TabContainer", box("panel", "line", 12, 6))
	t.set_stylebox("tab_hovered", "TabContainer", box("panel_focus", "line", 12, 6))
	t.set_stylebox("tab_focus", "TabContainer", ring(12, 6))
	for c: String in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		t.set_color(c, "TabContainer", Palette.color("text"))


static func _fields(t: Theme, pad_y: int) -> void:
	t.set_stylebox("normal", "LineEdit", box("background", "line", 8, pad_y))
	t.set_stylebox("focus", "LineEdit", ring(8, pad_y))
	t.set_stylebox("read_only", "LineEdit", box("panel", "line", 8, pad_y))
	t.set_color("font_color", "LineEdit", Palette.color("text"))
	t.set_color("font_placeholder_color", "LineEdit", Palette.color("text_dim"))
	t.set_color("caret_color", "LineEdit", Palette.color("accent"))
	t.set_stylebox("panel", "ItemList", box("background", "line", 6, 6))
	t.set_stylebox("focus", "ItemList", ring(6, 6))
	t.set_stylebox("selected", "ItemList", box("panel_focus", "accent", 4, 2))
	t.set_stylebox("selected_focus", "ItemList", box("panel_focus", "accent", 4, 2))
	t.set_color("font_color", "ItemList", Palette.color("text"))
	t.set_color("font_selected_color", "ItemList", Palette.color("text"))


## Dialogs and popup menus: the embedded window frame follows the palette.
static func _popups(t: Theme) -> void:
	# The frame grows past the window by its title bar (above) and a margin (other sides),
	# so the title and × sit on the panel, not on whatever is behind the dialog.
	var frame: StyleBoxFlat = box("panel", "line", 12, 36)
	frame.set_expand_margin_all(WINDOW_MARGIN)
	frame.expand_margin_top = WINDOW_TITLE_H
	t.set_constant("title_height", "Window", int(WINDOW_TITLE_H))
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_color("title_color", "Window", Palette.color("text"))
	t.set_font_size("title_font_size", "Window", HEADING_SIZE)
	t.set_stylebox("panel", "AcceptDialog", box("panel", "line", 8, 8))
	t.set_stylebox("panel", "PopupMenu", box("panel", "line", 4, 4))
	t.set_stylebox("hover", "PopupMenu", box("panel_focus", "accent", 4, 2))
	t.set_color("font_color", "PopupMenu", Palette.color("text"))
	t.set_color("font_hover_color", "PopupMenu", Palette.color("text"))
