class_name JoinAddress
extends RefCounted
## Manual join (FT-NET-013): turns what the player typed ("host", "host:port", an
## IPv4 or IPv6 literal, "[v6]:port", a LAN host name, or a ws:// URL) into the
## WebSocket URL to connect to, or a reason it can't.
##
## Provisional: any address is accepted, public ones included (VPNs such as Tailscale
## use non-private ranges); LAN only (FT-GEN-013) means the game offers no internet
## service, not that it filters what the player types.

## Provisional: the game's default WebSocket port (ServerMain.DEFAULT_PORT; net/
## can't name app/). Phase 2 should make ServerMain use this constant.
const DEFAULT_WS_PORT: int = 47800
const MAX_HOST_LENGTH: int = 253

## Set by parse(): ok with host, port and url, or not ok with a reason for the player.
var ok: bool = false
var host: String = ""
var port: int = 0
var url: String = ""
var error: String = ""


static func parse(text: String, default_port: int = DEFAULT_WS_PORT) -> JoinAddress:
	var r: JoinAddress = JoinAddress.new()
	var s: String = text.strip_edges()
	if s.is_empty():
		return r._fail("Enter the host's address, for example 192.168.1.20.")
	var scheme_at: int = s.find("://")
	if scheme_at >= 0:
		if s.substr(0, scheme_at).to_lower() != "ws":
			return r._fail("Enter the host's address or a ws:// address, not a web link.")
		s = s.substr(scheme_at + 3)
		if s.ends_with("/"):
			s = s.substr(0, s.length() - 1)
	if s.contains("/") or s.contains(" ") or s.contains("@"):
		return r._fail("That isn't a host address.")
	var h: String = s
	var port_text: String = ""
	if s.begins_with("["):
		var close: int = s.find("]")
		if close < 0:
			return r._fail("Missing ] after the IPv6 address.")
		h = s.substr(1, close - 1)
		var rest: String = s.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return r._fail("Unexpected text after the IPv6 address.")
			port_text = rest.substr(1)
		if not (h.contains(":") and h.is_valid_ip_address()):
			return r._fail("That isn't a valid IPv6 address.")
	elif s.count(":") == 1:
		h = s.get_slice(":", 0)
		port_text = s.get_slice(":", 1)
	elif s.count(":") > 1:
		if not s.is_valid_ip_address():
			return r._fail("That isn't a valid IPv6 address.")
	var reason: String = _host_problem(h)
	if not reason.is_empty():
		return r._fail(reason)
	var p: int = default_port
	if port_text != "" or s.ends_with(":"):
		if not port_text.is_valid_int() or port_text.begins_with("+"):
			return r._fail("The port must be a number from 1 to 65535.")
		p = port_text.to_int()
	if p < 1 or p > 65535:
		return r._fail("The port must be a number from 1 to 65535.")
	r.ok = true
	r.host = h
	r.port = p
	r.url = ws_url(h, p)
	return r


## ws://host:port, with an IPv6 literal in brackets.
static func ws_url(p_host: String, p_port: int) -> String:
	if p_host.contains(":"):
		return "ws://[%s]:%d" % [p_host, p_port]
	return "ws://%s:%d" % [p_host, p_port]


## "" if h is an IP literal or a well-formed host name, else the reason.
static func _host_problem(h: String) -> String:
	if h.is_empty():
		return "Enter the host's address before the port."
	if h.contains(":"):
		return "" if h.is_valid_ip_address() else "That isn't a valid IPv6 address."
	var dotted_digits: bool = true
	for c: String in h:
		if not (c == "." or c.is_valid_int()):
			dotted_digits = false
			break
	if dotted_digits:
		if h.is_valid_ip_address() and h.count(".") == 3:
			return ""
		return "That isn't a valid IPv4 address."
	if h.length() > MAX_HOST_LENGTH:
		return "That host name is too long."
	for label: String in h.split("."):
		if label.is_empty() or label.length() > 63:
			return "That isn't a valid host name."
		if label.begins_with("-") or label.ends_with("-"):
			return "That isn't a valid host name."
		for c: String in label:
			if not (c == "-" or c.is_valid_int() or (c.to_lower() >= "a" and c.to_lower() <= "z")):
				return "That isn't a valid host name."
	return ""


func _fail(reason: String) -> JoinAddress:
	ok = false
	error = reason
	return self
