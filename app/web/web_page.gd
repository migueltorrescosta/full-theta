class_name WebPage
extends RefCounted
## Facts about the browser page that GDScript can't see (D196, D200, FT-NET-046): its
## user agent, whether it was suspended and came back, the audio context's state. Backed
## by window.ft in app/web/shell.html. Off the web: empty user agent, no wakes, audio
## "running" (nothing to unlock).


## The browser's user agent, or "" off the web.
static func user_agent() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("navigator.userAgent", true))


## How many times the page came back after 2 s or more hidden (Safari suspends a page
## in the background; its socket may be dead on return), or the network came back.
## Compare with the last value: a change means "reconnect now".
static func wakes() -> int:
	if not OS.has_feature("web"):
		return 0
	return int(JavaScriptBridge.eval("window.ft ? window.ft.wakes : 0", true))


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
