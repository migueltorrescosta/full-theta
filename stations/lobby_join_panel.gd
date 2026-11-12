class_name LobbyJoinPanel
extends VBoxContainer
## The host's "How to join" content in the lobby (FT-NET-013): the browser URL with its QR
## code and the desktop address, or why nobody else can join a loopback server. The URL says
## https when the host's server serves the page over TLS. The lobby's join strip (Strip) and
## name prompt (NamePrompt) live here too.


func _init(ctx: StationContext) -> void:
	name = "JoinPanel"
	if is_local_only(ctx.host_bind):
		var local: Label = _line("JoinLocal", tr("lobby.join_local") % ctx.host_bind)
		local.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		local.custom_minimum_size = Vector2(320, 0)
		return
	var url: String = join_url(ctx.host_bind, ctx.host_port, ctx.host_tls)
	_line("JoinUrl", tr("lobby.join_browser") % url)
	_line("JoinDesktop", tr("lobby.join_desktop") % ctx.host_bind)
	var qr: QrCode = QrCode.new()
	qr.name = "JoinQr"
	qr.set_text(url)
	add_child(qr)


## The browser URL of the host's web stations (https with TLS): HTTP listens one port below
## the WebSocket port (D108, docs/launch.md).
static func join_url(bind: String, ws_port: int, secure: bool = false) -> String:
	return "%s://%s:%d/?join=1" % ["https" if secure else "http", bind, ws_port - 1]


## True for an address only this computer can reach.
static func is_local_only(bind: String) -> bool:
	return bind.begins_with("127.") or bind == "::1" or bind == "localhost"


func _line(node_name: String, text: String) -> Label:
	var l: Label = Label.new()
	l.name = node_name
	l.text = text
	add_child(l)
	return l


## The host's join strip (#35 A6): the browser URL's QR code and the address beside it in
## large type, under the title row; none on a loopback server (the dialog says why). Compact
## on a phone (`fit`).
class Strip:
	extends HBoxContainer

	## The QR module size and address font size, in px, off a phone and on one.
	const QR_PX: int = 4
	const QR_PX_PHONE: int = 2
	const ADDRESS_SIZE: int = 40
	const ADDRESS_SIZE_PHONE: int = 22

	var _ctx: StationContext
	var _qr: QrCode
	var _address: Label

	func _init(ctx: StationContext) -> void:
		_ctx = ctx
		name = "JoinStrip"
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 12)
		_qr = QrCode.new()
		_qr.name = "JoinStripQr"
		_qr.module_px = QR_PX
		_qr.set_text(LobbyJoinPanel.join_url(ctx.host_bind, ctx.host_port, ctx.host_tls))
		add_child(_qr)
		var col: VBoxContainer = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(col)
		var caption: Label = Label.new()
		caption.text = tr("lobby.join_scan")
		caption.theme_type_variation = "DimLabel"
		caption.name = "JoinStripCaption"
		col.add_child(caption)
		_address = Label.new()
		_address.text = ctx.host_bind
		_address.name = "JoinStripAddress"
		_address.add_theme_font_size_override("font_size", ADDRESS_SIZE)
		col.add_child(_address)

	## The strip for the host's lobby, or null off the host or on a loopback server.
	static func for_host(ctx: StationContext) -> Strip:
		if ctx.host_bind == "" or LobbyJoinPanel.is_local_only(ctx.host_bind):
			return null
		return Strip.new(ctx)

	## The strip's sizes: compact on a phone.
	func fit(phone: bool) -> void:
		_qr.module_px = QR_PX_PHONE if phone else QR_PX
		_qr.set_text(LobbyJoinPanel.join_url(_ctx.host_bind, _ctx.host_port, _ctx.host_tls))
		_address.add_theme_font_size_override(
			"font_size", ADDRESS_SIZE_PHONE if phone else ADDRESS_SIZE
		)


## The name prompt (#35 A5): a field and Done, shown while the player has no name of their own
## (a phone that joined by QR code); Done saves the name and renames the player on the server.
class NamePrompt:
	extends HBoxContainer

	var field: LineEdit
	var _ctx: StationContext

	func _init(ctx: StationContext) -> void:
		_ctx = ctx
		name = "NamePrompt"
		field = LineEdit.new()
		field.name = "NameField"
		field.placeholder_text = tr("menu.name")
		field.max_length = NetProtocol.MAX_NAME_BYTES
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.text_submitted.connect(func(_t: String) -> void: submit_name())
		add_child(field)
		var done: Button = Button.new()
		done.name = "NameDone"
		done.text = tr("lobby.done")
		done.pressed.connect(submit_name)
		add_child(done)
		visible = ctx.settings != null and not ctx.settings.has_name()

	## Takes the prompt's name: saved, sent to the server, and the prompt goes. An empty field
	## keeps the prompt.
	func submit_name() -> void:
		var n: String = field.text.strip_edges()
		if n == "":
			return
		_ctx.settings.player_name = n
		_ctx.settings.save()
		_ctx.intents.rename(n)
		visible = false
