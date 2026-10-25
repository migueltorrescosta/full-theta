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
##   CrewLabel (small, accent).
## - Button: TouchButton, OptionButton: TouchOptionButton, CheckBox: TouchCheckBox -
##   targets at least TOUCH_MIN px tall at 100 %, for the touch layouts.
## - Button: LoadCell_intense, LoadCell_busy, LoadCell_light, LoadCell_none - the lobby's
##   station cells, bordered in the load colour.

## The smallest touch target, in px at 100 % UI scale.
const TOUCH_MIN: int = 44
const FONT_SIZE: int = 16
const TITLE_SIZE: int = 32
const HEADING_SIZE: int = 20
const SMALL_SIZE: int = 12
const RADIUS: int = 8
const BORDER: int = 1
## The focus ring's width.
const RING: int = 2
const SPACING: int = 8
## Vertical content margin of a touch control: with the font's line height it reaches
## TOUCH_MIN.
const TOUCH_PAD: int = 12
const CELL_PAD: int = 8
const LOAD_VARIANTS: Array[String] = ["intense", "busy", "light", "none"]


## A fresh theme. The result is a plain resource; `apply` puts it on a window.
static func build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = FONT_SIZE
	_labels(t)
	_buttons(t, "Button", "", 8, 4)
	_buttons(t, "Button", "TouchButton", 16, TOUCH_PAD)
	_buttons(t, "OptionButton", "", 8, 4)
	_buttons(t, "OptionButton", "TouchOptionButton", 16, TOUCH_PAD)
	_check(t, "CheckBox", "", 4)
	_check(t, "CheckBox", "TouchCheckBox", TOUCH_PAD)
	for tag: String in LOAD_VARIANTS:
		_cell(t, tag)
	_panels(t)
	_fields(t)
	_popups(t)
	t.set_constant("separation", "VBoxContainer", SPACING)
	t.set_constant("separation", "HBoxContainer", SPACING)
	t.set_constant("h_separation", "GridContainer", SPACING)
	t.set_constant("v_separation", "GridContainer", SPACING)
	return t


## Puts the theme on the window, so every Control below inherits it.
static func apply(window: Window) -> void:
	window.theme = build()


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
	t.set_color("font_color", "CrewLabel", Palette.color("accent"))


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
	t.set_stylebox("normal", name, normal)
	t.set_stylebox("hover", name, chosen)
	t.set_stylebox("pressed", name, chosen)
	t.set_stylebox("hover_pressed", name, chosen)
	t.set_stylebox("disabled", name, off)
	t.set_stylebox("focus", name, ring(CELL_PAD, CELL_PAD))
	t.set_color("font_disabled_color", name, Palette.color("text_dim"))


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


static func _fields(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", box("background", "line", 8, 6))
	t.set_stylebox("focus", "LineEdit", ring(8, 6))
	t.set_stylebox("read_only", "LineEdit", box("panel", "line", 8, 6))
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
	t.set_stylebox("embedded_border", "Window", box("panel", "line", 12, 36))
	t.set_stylebox("embedded_unfocused_border", "Window", box("panel", "line", 12, 36))
	t.set_color("title_color", "Window", Palette.color("text"))
	t.set_font_size("title_font_size", "Window", HEADING_SIZE)
	t.set_stylebox("panel", "AcceptDialog", box("panel", "line", 8, 8))
	t.set_stylebox("panel", "PopupMenu", box("panel", "line", 4, 4))
	t.set_stylebox("hover", "PopupMenu", box("panel_focus", "accent", 4, 2))
	t.set_color("font_color", "PopupMenu", Palette.color("text"))
	t.set_color("font_hover_color", "PopupMenu", Palette.color("text"))
