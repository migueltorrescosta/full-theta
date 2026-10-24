class_name JoinHelpers
extends RefCounted
## Web join helpers (FT-NET-030, D196): a browser station joins the host that served its
## page at once, with nothing typed; ?join=0 only pre-fills the address. The host serves
## the page over HTTP on the WebSocket port minus one (D108, app/host_session.gd). The
## test hooks ?pick=ENTRY and ?ready=1 take a station and press Ready (tools/l4/web.sh;
## they act only when a server offers the station). The logic takes the page
## facts as inputs so it needs no browser; only web_config() reads JavaScriptBridge.


## The join address to pre-fill and whether to join at once.
class WebJoinConfig:
	extends RefCounted
	## "host" or "host:port"; empty when there is nothing to pre-fill.
	var address: String = ""
	## True unless the query string has join=0.
	var auto_join: bool = false
	## Test hooks (?pick=ENTRY, ?ready=1): the station to take and whether to press Ready.
	var pick: String = ""
	var ready: bool = false


## Builds the config from the page's hostname, port (0 when the URL names none) and
## query string (with or without the leading "?"). The address carries the WebSocket
## port (page port + 1) unless that is the default one, so it stays short.
static func config_from(hostname: String, page_port: int, search: String) -> WebJoinConfig:
	var cfg: WebJoinConfig = WebJoinConfig.new()
	var host: String = hostname.strip_edges()
	if host.is_empty():
		return cfg
	if host.contains(":"):
		host = "[%s]" % host
	cfg.address = host
	var ws_port: int = page_port + 1
	if page_port > 0 and ws_port != NetProtocol.DEFAULT_WS_PORT and ws_port <= 65535:
		cfg.address = "%s:%d" % [host, ws_port]
	var query: PackedStringArray = search.trim_prefix("?").split("&")
	cfg.auto_join = not query.has("join=0")
	cfg.ready = query.has("ready=1")
	for item: String in query:
		if item.begins_with("pick="):
			cfg.pick = item.trim_prefix("pick=").uri_decode()
	return cfg


## The config of the running page; empty off the web.
static func web_config() -> WebJoinConfig:
	if not OS.has_feature("web"):
		return WebJoinConfig.new()
	var hostname: String = str(JavaScriptBridge.eval("location.hostname", true))
	var port: String = str(JavaScriptBridge.eval("location.port", true))
	var search: String = str(JavaScriptBridge.eval("location.search", true))
	return config_from(hostname, port.to_int(), search)
