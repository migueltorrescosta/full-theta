class_name LayoutMode
extends RefCounted
## Which layout a client uses, chosen at runtime from the viewport size and the pointer
## kind, never from the build (FT-STN-005, D194, D195, D216): desktop (a fine pointer),
## touch (a coarse pointer, tablet sized: targets of at least 44 px) and phone (the short
## side under PHONE_SHORT). Touch and phone change sizes and arrangement only, never what
## a station can do (FT-NET-018). A portrait viewport stacks the main area above the
## radar column; a landscape one puts them side by side, on every device (D216).
##
## `apply` puts the matching theme on a window and keeps it matching on resize and
## rotation; screens ask `kind_of` / `portrait` for their arrangement and listen to the
## viewport's `size_changed`.

enum Kind { DESKTOP, TOUCH, PHONE }

## The short side (px at 100 % UI scale) under which a viewport is a phone.
const PHONE_SHORT: float = 600.0

## Tests and L5 shots force a kind (-1 follows the device).
static var forced: int = -1
static var _themes: Dictionary = {}


## The layout kind for a viewport of `size` and a pointer that is coarse or not.
static func kind_for(size: Vector2, coarse: bool) -> Kind:
	if forced >= 0:
		return forced as Kind
	if minf(size.x, size.y) < PHONE_SHORT:
		return Kind.PHONE
	return Kind.TOUCH if coarse else Kind.DESKTOP


## True for the touch and phone layouts.
static func is_touch(kind: Kind) -> bool:
	return kind != Kind.DESKTOP


## True when the viewport is taller than it is wide.
static func portrait(size: Vector2) -> bool:
	return size.y > size.x


## The kind of the viewport a node is in.
static func kind_of(node: Node) -> Kind:
	return kind_for(node.get_viewport().get_visible_rect().size, coarse_pointer())


## Whether the primary pointer is a finger: a touch screen, or in a browser the page's
## `(pointer: coarse)` media query.
static func coarse_pointer() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches"))
	return DisplayServer.is_touchscreen_available()


## The theme of a layout kind (built once).
static func theme_for(kind: Kind) -> Theme:
	var touch: bool = is_touch(kind)
	if not _themes.has(touch):
		_themes[touch] = UiTheme.build(touch)
	return _themes[touch]


## Sets the theme of the window's current layout and re-sets it when the window is
## resized into another kind.
static func apply(window: Window) -> void:
	_set_theme(window)
	if not window.size_changed.is_connected(_set_theme.bind(window)):
		window.size_changed.connect(_set_theme.bind(window))


static func _set_theme(window: Window) -> void:
	var kind: Kind = kind_for(Vector2(window.get_visible_rect().size), coarse_pointer())
	var theme: Theme = theme_for(kind)
	if window.theme != theme:
		window.theme = theme
