class_name WebLoadStage
extends RefCounted
## Tells the page which stage the start-up is in, for the loading screen (app/web/shell.html,
## ft.loadStage; #11, DC2). The page shows the download itself and "start" before the engine
## runs; the game reports the rest. Off the web: no effect.

## The game starts joining the server.
const CONNECT: String = "connect"
## The server welcomed the client; the lobby is being built.
const LOBBY: String = "lobby"
## The lobby (or, when joining failed, the menu) is up: the page removes its loading screen.
const READY: String = "ready"
const STAGES: Array[String] = [CONNECT, LOBBY, READY]


## Reports `stage` (one of STAGES) to the page.
static func report(stage: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.ft && window.ft.loadStage(%s)" % JSON.stringify(stage), true)
