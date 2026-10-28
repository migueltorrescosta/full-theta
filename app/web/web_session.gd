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
## The language whose voice pack was fetched or is being fetched.
var _voice_lang: String = ""
var _voice_request: HTTPRequest


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
	var lines: LocalLines = shell.voice.local_lines if shell.voice != null else null
	if lines != null and lines.lang != _voice_lang and _voice_request == null:
		_fetch_voice(lines.lang)
	var layout: String = LayoutMode.Kind.keys()[LayoutMode.kind_of(shell)].to_lower()
	if layout != _layout:
		_layout = layout
		WebPage.set_layout(layout)


## The voice pack's URL next to the page at `page_href` (query and fragment dropped).
static func voice_pack_url(page_href: String, lang: String) -> String:
	var base: String = page_href.get_slice("#", 0).get_slice("?", 0)
	return base.substr(0, base.rfind("/") + 1) + "voice-%s.pack" % lang


## Fetches `lang`'s voice pack once per page; on failure the lines stay subtitles only.
func _fetch_voice(lang: String) -> void:
	_voice_lang = lang
	if LocalLines.has_pack(lang):
		return
	var href: String = str(JavaScriptBridge.eval("location.href", true))
	_voice_request = HTTPRequest.new()
	add_child(_voice_request)
	_voice_request.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			var pack: VoicePack = (
				VoicePack.parse(body)
				if result == HTTPRequest.RESULT_SUCCESS and code == 200
				else null
			)
			if pack != null and pack.language == lang:
				LocalLines.add_pack(pack)
			else:
				push_warning(
					"voice pack %s: not loaded (result %d, HTTP %d)" % [lang, result, code]
				)
			_voice_request.queue_free()
			_voice_request = null
	)
	if _voice_request.request(voice_pack_url(href, lang)) != OK:
		_voice_request.queue_free()
		_voice_request = null


func _exit_tree() -> void:
	KeepAwake.stop()
