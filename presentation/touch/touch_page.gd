class_name TouchPage
extends RefCounted
## What the touch widgets ask the browser page (#28), backed by window.ft in
## app/web/shell.html: the safe-area insets and the fullscreen button's tap. Kept here,
## not in app/web/WebPage, because presentation/ may not use app/ (spec §2.2). Off the
## web: no insets, no fullscreen.


## The page's safe-area insets (notch, home indicator; `env(safe-area-inset-*)`) in
## canvas pixels, as left, top, right, bottom in x, y, z, w (#28). Zero off the web.
static func safe_insets() -> Vector4:
	if not OS.has_feature("web"):
		return Vector4.ZERO
	var parsed: Variant = JSON.parse_string(
		str(JavaScriptBridge.eval("window.ft ? window.ft.safeArea() : ''", true))
	)
	if not parsed is Dictionary:
		return Vector4.ZERO
	var d: Dictionary = parsed
	var k: float = float(JavaScriptBridge.eval("window.ft ? window.ft.canvasScale() : 1", true))
	return Vector4(float(d["l"]), float(d["t"]), float(d["r"]), float(d["b"])) * k


## Whether the page offers fullscreen with a landscape lock: Android and iPad browsers
## that aren't fullscreen yet; never an iPhone, which can't (#28). False off the web.
static func fullscreen_offered() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("!!(window.ft && window.ft.fullscreenOffered())", true))


## Registers a button whose tap the page itself acts on, inside the tap's handler (the
## only place a browser allows fullscreen): `rect` in canvas pixels, `action` "fullscreen".
static func set_action(id: String, rect: Rect2, action: String) -> void:
	if not OS.has_feature("web"):
		return
	var call: String = (
		"ft.setAction(%s,%d,%d,%d,%d,%s)"
		% [
			JSON.stringify(id),
			roundi(rect.position.x),
			roundi(rect.position.y),
			roundi(rect.size.x),
			roundi(rect.size.y),
			JSON.stringify(action)
		]
	)
	JavaScriptBridge.eval(call, true)


## Removes a button set with `set_action`.
static func clear_action(id: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("ft.clearAction(%s)" % JSON.stringify(id), true)
