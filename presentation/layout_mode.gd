class_name LayoutMode
extends RefCounted
## Which layout a client uses, chosen at runtime from the window's physical size and the
## pointer kind, never from the build and never from the UI scale (FT-STN-005, D194, D195,
## D216, D223): desktop (a fine pointer), touch (a coarse pointer, tablet sized: targets
## of at least 44 px) and phone (the short side under PHONE_SHORT). The size is measured
## in device-independent pixels: window pixels divided by the screen density (the screen
## DPI over 96 on a desktop, `devicePixelRatio` in a browser), so a 1280 x 720 desktop at
## 150 % UI scale is still a desktop and a 390 x 844 CSS-px phone at dpr 3 is a phone. Touch and phone change sizes and arrangement only, never what
## a station can do (FT-NET-018). A portrait viewport stacks the main area above the
## radar column; a landscape one puts them side by side, on every device (D216).
##
## `apply` puts the matching theme on a window and keeps it matching on resize and
## rotation; screens ask `kind_of` / `portrait` for their arrangement and listen to the
## viewport's `size_changed`.

enum Kind { DESKTOP, TOUCH, PHONE }

## The short side (device-independent px) under which a window is a phone.
const PHONE_SHORT: float = 600.0

## Tests and L5 shots force a kind (-1 follows the device).
static var forced: int = -1
static var _themes: Dictionary = {}


## The layout kind for a window of `size` device-independent pixels (`dp_size`) and a
## pointer that is coarse or not.
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
	return kind_for(dp_size_of(node.get_viewport()), coarse_pointer())


## The window size in device-independent pixels: the visible rect (already divided by the
## UI scale `ui_scale`) back to window pixels, over the screen `density` (1 = 96 dpi).
static func dp_size(visible: Vector2, ui_scale: float, density: float) -> Vector2:
	return visible * ui_scale / maxf(density, 0.1)


## `dp_size` of a viewport, with this device's density.
static func dp_size_of(viewport: Viewport) -> Vector2:
	var ui_scale: float = 1.0
	if viewport is Window:
		ui_scale = (viewport as Window).content_scale_factor
	return dp_size(viewport.get_visible_rect().size, ui_scale, density())


## The screen density: the browser's `devicePixelRatio`, else the screen DPI over 96.
static func density() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	return clampf(float(DisplayServer.screen_get_dpi()) / 96.0, 1.0, 4.0)


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
	var kind: Kind = kind_for(dp_size_of(window), coarse_pointer())
	var theme: Theme = theme_for(kind)
	if window.theme != theme:
		window.theme = theme
