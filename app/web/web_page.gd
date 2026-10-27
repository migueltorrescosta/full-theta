class_name WebPage
extends RefCounted
## Facts about the browser page that GDScript can't see (D196, D200, FT-NET-046): its
## user agent, whether it was suspended and came back, the audio context's state. Backed
## by window.ft in app/web/shell.html. Off the web: empty user agent, no wake callbacks,
## audio "running" (nothing to unlock).


## The browser's user agent, or "" off the web.
static func user_agent() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("navigator.userAgent", true))


## Calls `on_wake` (no arguments) each time the page came back after 2 s or more hidden
## (Safari suspends a page in the background; its socket may be dead on return), or the
## network came back. Returns the callback object to keep alive, or null off the web.
static func on_wake(on_wake_fn: Callable) -> JavaScriptObject:
	if not OS.has_feature("web"):
		return null
	var cb: JavaScriptObject = JavaScriptBridge.create_callback(
		func(_args: Array) -> void: on_wake_fn.call()
	)
	JavaScriptBridge.get_interface("ft").call("setOnWake", cb)
	return cb


## "running", "suspended" (waiting for a tap) or "" before the engine's audio started.
static func audio_state() -> String:
	if not OS.has_feature("web"):
		return "running"
	return str(JavaScriptBridge.eval("window.ft ? window.ft.audioState() : ''", true))


## Tells the page which panel the player is on, for the browser smoke test
## (tools/l4/web.sh reads window.ftPanel). No effect off the web.
static func set_panel(entry: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ftPanel = %s" % JSON.stringify(entry), true)


## Tells the page which layout the client chose ("desktop", "touch" or "phone",
## LayoutMode), for the browser smoke test. No effect off the web.
static func set_layout(kind: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ftLayout = %s" % JSON.stringify(kind), true)


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
