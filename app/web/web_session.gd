class_name WebSession
extends Node
## What a browser station does beside the ordinary client session (MainMenu adds one to its
## ClientShell in a browser build, nothing elsewhere): keeps the tablet awake while joined
## (FT-NET-046), reconnects with its token when the page comes back from a suspension or
## the network returns (without a reload, D108), tells the page which panel it shows
## (WebPage.set_panel, for tools/l4/web.sh), and runs the ?pick= test hooks
## (WebAutoplay).

var shell: ClientShell
var _wakes: int = 0
var _awake: bool = false
var _panel: String = ""


## Adds a WebSession to `shell` in a browser build.
static func attach(shell_node: ClientShell) -> void:
	if not OS.has_feature("web"):
		return
	var s: WebSession = WebSession.new()
	s.shell = shell_node
	shell_node.add_child(s)
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.web_config()
	if cfg.pick != "":
		var a: WebAutoplay = WebAutoplay.new()
		a.client = shell_node.ctx.client
		a.crew = shell_node.ctx.crew
		a.entry = cfg.pick
		a.press_ready = cfg.ready
		s.add_child(a)


func _ready() -> void:
	_wakes = WebPage.wakes()


func _process(_delta: float) -> void:
	var client: NetClient = shell.ctx.client
	if client.is_welcomed() and not _awake:
		_awake = true
		KeepAwake.start()
	var wakes: int = WebPage.wakes()
	if wakes != _wakes:
		_wakes = wakes
		# The socket may look open and be dead; resume() replaces it and the server hands
		# the same session back with a full snapshot (FT-NET-025).
		if client.state != NetClient.State.REJECTED:
			client.resume()
	var panel: String = "lobby"
	if shell.screen != null:
		panel = shell.ctx.crew.entry
	if panel != _panel:
		_panel = panel
		WebPage.set_panel(panel)


func _exit_tree() -> void:
	KeepAwake.stop()
