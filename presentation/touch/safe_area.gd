class_name SafeArea
extends RefCounted
## The part of the window no notch, home indicator or system gesture covers (#28). The
## browser page fills the screen edge to edge (`viewport-fit=cover` in app/web/shell.html)
## and reports `env(safe-area-inset-*)`; screens keep their controls inside `safe_rect`
## and every tap target above `tap_bottom`.
##
## On a phone (LayoutMode.Form PHONE_*) each side is at least FLOOR px (the shell's
## `max(8px, env(...))`) and the bottom GESTURE_BAND px take no taps (the iOS home
## indicator and Android's gesture bar). Tablets and desktops use the raw insets, zero
## off the web. A native window is never a touch phone, so off the web (and unless
## simulating) a phone-sized window keeps no floor and no band. Every value is in the
## viewport's pixels (after the UI scale), so a control's global rect compares with them
## directly.
##
## L5 shots and tests simulate a device with `simulate([l, t, r, b])`, insets in device-
## independent (CSS) px, and `simulate([])` to stop.

## Least margin on each side of a phone, in device-independent px.
const FLOOR: float = 8.0
## Bottom strip of a phone that takes no taps, in device-independent px.
const GESTURE_BAND: float = 24.0

## True while `simulated` replaces the page's insets.
static var simulating: bool = false
## Simulated insets (left, top, right, bottom in x, y, z, w), device-independent px.
static var simulated: Vector4 = Vector4.ZERO


## Simulates a device's insets [left, top, right, bottom] in device-independent px; an
## empty array goes back to the real ones.
static func simulate(insets: Array) -> void:
	simulating = insets.size() == 4
	simulated = Vector4.ZERO
	if simulating:
		simulated = Vector4(insets[0], insets[1], insets[2], insets[3])


## The raw insets of the window, in window (canvas) px: left, top, right, bottom.
static func raw_insets() -> Vector4:
	if simulating:
		return simulated * LayoutMode.density()
	return TouchPage.safe_insets()


## The margins a screen keeps on each side (left, top, right, bottom in x, y, z, w), in
## the viewport's px: the raw insets, at least FLOOR on a phone.
static func margins(node: Node) -> Vector4:
	var raw: Vector4 = raw_insets()
	return _margins(raw, _form(node), LayoutMode.density(), _factor(node))


## The pure part of `margins`: `raw` in window px, `density` window px per dp, `factor` the
## UI scale (window px per viewport px).
static func _margins(raw: Vector4, form: LayoutMode.Form, density: float, factor: float) -> Vector4:
	var m: Vector4 = raw
	if LayoutMode.is_phone(form):
		var least: float = FLOOR * density
		m = Vector4(maxf(m.x, least), maxf(m.y, least), maxf(m.z, least), maxf(m.w, least))
	return m / maxf(factor, 0.01)


## The bottom strip that takes no taps, in the viewport's px: the bottom inset, at least
## GESTURE_BAND on a phone.
static func tap_band(node: Node) -> float:
	return _band(raw_insets().w, _form(node), LayoutMode.density(), _factor(node))


static func _band(raw_bottom: float, form: LayoutMode.Form, density: float, factor: float) -> float:
	var band: float = raw_bottom
	if LayoutMode.is_phone(form):
		band = maxf(band, GESTURE_BAND * density)
	return band / maxf(factor, 0.01)


## The safe rectangle of the node's viewport, in viewport px.
static func safe_rect(node: Node) -> Rect2:
	var vp: Rect2 = node.get_viewport().get_visible_rect()
	var m: Vector4 = margins(node)
	return Rect2(vp.position + Vector2(m.x, m.y), vp.size - Vector2(m.x + m.z, m.y + m.w))


## Where taps may go: the safe rectangle above the gesture band, in viewport px.
static func tap_rect(node: Node) -> Rect2:
	var r: Rect2 = safe_rect(node)
	var bottom: float = node.get_viewport().get_visible_rect().end.y - tap_band(node)
	r.size.y = minf(r.end.y, bottom) - r.position.y
	return r


## The lowest y a tap target may reach, in viewport px.
static func tap_bottom(node: Node) -> float:
	return tap_rect(node).end.y


## `rect` (viewport px) in a control's local coordinates.
static func to_local(control: Control, rect: Rect2) -> Rect2:
	return control.get_global_transform().affine_inverse() * rect


## The node's form, or DESKTOP for a native window (no touch phone off the web).
static func _form(node: Node) -> LayoutMode.Form:
	if not simulating and not OS.has_feature("web"):
		return LayoutMode.Form.DESKTOP
	return LayoutMode.form_of(node)


static func _factor(node: Node) -> float:
	var w: Window = node.get_viewport() as Window
	return w.content_scale_factor if w != null else 1.0
