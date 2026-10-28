class_name LobbyJoinPanel
extends VBoxContainer
## The host's "How to join" content in the lobby (FT-NET-013): the browser URL with its QR
## code and the desktop address, or why nobody else can join a loopback server. The URL says
## https when the host's server serves the page over TLS.


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
	var qr: QrView = QrView.new()
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
