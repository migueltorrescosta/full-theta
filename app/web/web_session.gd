class_name WebSession
extends Node
## What a browser station does beside the ordinary client session (MainMenu adds one to its
## ClientShell in a browser build, nothing elsewhere): keeps the tablet awake while joined
## (FT-NET-046), reconnects with its token when the page comes back from a suspension or
## the network returns (without a reload, D108), tells the page which panel and layout it shows
## (WebPage.set_panel, WebPage.set_layout, for tools/l4/web.sh), and runs the ?pick= test hooks
## (WebAutoplay), and fetches the session language's voice pack once the welcome names it
## (D294: the web export ships the prerendered lines per language, not in its pack).

var shell: ClientShell
var _woken: bool = false
var _wake_callback: JavaScriptObject
var _awake: bool = false
var _panel: String = ""
var _layout: String = ""
## The language whose voice pack was fetched or is being fetched, and whether the page's
## fetch is still running.
var _voice_lang: String = ""
var _voice_pending: bool = false


## Adds a WebSession to `shell` in a browser build.
static func attach(shell_node: ClientShell) -> void:
	if not OS.has_feature("web"):
		return
	var s: WebSession = WebSession.new()
	s.shell = shell_node
	shell_node.add_child(s)
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.web_config()
	if cfg.pick != "":
		shell_node.ctx.settings.skip_first_visit_help = true
		var a: WebAutoplay = WebAutoplay.new()
		a.client = shell_node.ctx.client
		a.crew = shell_node.ctx.crew
		a.entry = cfg.pick
		a.press_ready = cfg.ready
		s.add_child(a)


func _ready() -> void:
	_wake_callback = WebPage.on_wake(func() -> void: _woken = true)


func _process(_delta: float) -> void:
	var client: NetClient = shell.ctx.client
	if client.is_welcomed() and not _awake:
		_awake = true
		KeepAwake.start()
	if _woken:
		_woken = false
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
		WebLoadStage.report(WebLoadStage.READY)
	var lines: LocalLines = shell.voice.local_lines if shell.voice != null else null
	if _voice_pending:
		_take_voice()
	elif lines != null and lines.lang != _voice_lang:
		_fetch_voice(lines.lang)
	var layout: String = LayoutMode.Kind.keys()[LayoutMode.kind_of(shell)].to_lower()
	if layout != _layout:
		_layout = layout
		WebPage.set_layout(layout)


## Fetches `lang`'s voice pack once per page, with the page's own fetch from next to the
## page (the host that served it); on failure the lines stay subtitles only.
func _fetch_voice(lang: String) -> void:
	_voice_lang = lang
	if LocalLines.has_pack(lang):
		return
	_voice_pending = true
	var url: String = JSON.stringify("voice-%s.pack" % lang)
	JavaScriptBridge.eval(
		(
			(
				"window.ftVoicePack = -1; fetch(%s).then(r => r.ok ? r.arrayBuffer() : null)"
				+ ".then(b => { window.ftVoicePack = b ? new Uint8Array(b) : 0; },"
				+ " () => { window.ftVoicePack = 0; });"
			)
			% url
		),
		true
	)


## Takes the fetched pack once the page has it (bytes; -1 while fetching, 0 on failure).
func _take_voice() -> void:
	var got: Variant = JavaScriptBridge.eval("window.ftVoicePack", true)
	if (got is int or got is float) and int(got) == -1:
		return
	_voice_pending = false
	JavaScriptBridge.eval("window.ftVoicePack = undefined;", true)
	var pack: VoicePack = VoicePack.parse(got) if got is PackedByteArray else null
	if pack != null and pack.language == _voice_lang:
		LocalLines.add_pack(pack)
		print("voice pack %s: %d lines" % [_voice_lang, pack.size()])
	else:
		push_warning("voice pack %s: not loaded" % _voice_lang)


func _exit_tree() -> void:
	KeepAwake.stop()
