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
