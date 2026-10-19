class_name LanBrowser
extends RefCounted
## Client side of LAN discovery and manual join (FT-NET-012, FT-NET-013): listens for
## LanBeacon datagrams and keeps the list of hosts seen in the last EXPIRY_USEC, and
## parses a typed address (parse_address). No timer or Node: the client calls
## poll(now_usec) each frame.
##
## One listener per machine: Godot 4.7's PacketPeerUDP doesn't set SO_REUSEADDR, so
## a second client on the same machine gets an error from start() (checked on
## fugaku). That client still joins by manual address (parse_address), e.g. the
## host's own client, which joins its server directly anyway (FT-NET-001).


## One discovered server, keyed by sender address and WebSocket port.
class Host:
	extends RefCounted
	var address: String
	var ws_port: int
	var http_port: int
	var name: String
	var protocol: int
	var players: int
	var cap: int
	var running: bool
	## False when the server speaks another protocol version: listed, not hidden, so
	## the player sees why it can't be joined (FT-NET-005).
	var compatible: bool
	var last_seen_usec: int

	func key() -> String:
		return "%s|%d" % [address, ws_port]

	func url() -> String:
		return LanBrowser.ws_url(address, ws_port)


## A typed address (parse_address): ok with host, port and url, or not ok with a
## reason for the player.
class Address:
	extends RefCounted
	var ok: bool = false
	var host: String = ""
	var port: int = 0
	var url: String = ""
	var error: String = ""

	func fail(reason: String) -> Address:
		ok = false
		error = reason
		return self


## Hosts silent for longer than this are dropped (3.5 beacon intervals).
const EXPIRY_USEC: int = 3_500_000
const MAX_PACKETS_PER_POLL: int = 64
const MAX_HOST_LENGTH: int = 253

var protocol_version: int
## Datagrams ignored as malformed or with the wrong magic, for diagnostics.
var ignored: int = 0

var _peer: PacketPeerUDP
var _hosts: Dictionary[String, Host] = {}


func _init(p_protocol_version: int) -> void:
	protocol_version = p_protocol_version


## Binds the discovery port. Port 0 binds an ephemeral port (tests); read it back
## with local_port(). Returns the bind error, e.g. when another client on this
## machine already listens.
func start(port: int = LanBeacon.DISCOVERY_PORT, bind_address: String = "*") -> Error:
	stop()
	_peer = PacketPeerUDP.new()
	var err: Error = _peer.bind(port, bind_address) as Error
	if err != OK:
		_peer = null
	return err


func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_hosts.clear()


func is_listening() -> bool:
	return _peer != null and _peer.is_bound()


func local_port() -> int:
	return _peer.get_local_port() if _peer != null else 0


## Reads pending datagrams and expires silent hosts. Returns true if the list changed.
func poll(now_usec: int) -> bool:
	var changed: bool = false
	if _peer != null:
		var n: int = 0
		while _peer.get_available_packet_count() > 0 and n < MAX_PACKETS_PER_POLL:
			var data: PackedByteArray = _peer.get_packet()
			changed = ingest(data, _peer.get_packet_ip(), now_usec) or changed
			n += 1
	for key: String in _hosts.keys():
		if now_usec - _hosts[key].last_seen_usec > EXPIRY_USEC:
			_hosts.erase(key)
			changed = true
	return changed


## Takes one datagram from sender_ip. Public so tests can feed packets without a
## socket. Returns true if a host was added or its fields changed.
func ingest(data: PackedByteArray, sender_ip: String, now_usec: int) -> bool:
	var d: Dictionary = LanBeacon.decode(data)
	if d.is_empty() or sender_ip.is_empty():
		ignored += 1
		return false
	var h: Host = Host.new()
	h.address = sender_ip
	h.ws_port = d["ws_port"]
	h.http_port = d["http_port"]
	h.name = d["name"]
	h.protocol = d["protocol"]
	h.players = d["players"]
	h.cap = d["cap"]
	h.running = d["running"]
	h.compatible = h.protocol == protocol_version
	h.last_seen_usec = now_usec
	var old: Host = _hosts.get(h.key())
	_hosts[h.key()] = h
	return old == null or _summary(old) != _summary(h)


## Current hosts, compatible first, then by name and address.
func hosts() -> Array[Host]:
	var out: Array[Host] = []
	out.assign(_hosts.values())
	out.sort_custom(_before)
	return out


static func _before(a: Host, b: Host) -> bool:
	if a.compatible != b.compatible:
		return a.compatible
	if a.name != b.name:
		return a.name.naturalnocasecmp_to(b.name) < 0
	return a.key() < b.key()


static func _summary(h: Host) -> Array:
	return [h.http_port, h.name, h.protocol, h.players, h.cap, h.running]


## Manual join (FT-NET-013): turns what the player typed ("host", "host:port", an IPv4
## or IPv6 literal, "[v6]:port", a LAN host name, or a ws:// URL) into the WebSocket
## URL to connect to, or a reason it can't.
##
## Any address is accepted, public ones included (VPNs such as Tailscale use
## non-private ranges); LAN only (FT-GEN-013) means the game offers no internet
## service, not that it filters what the player types. Provisional: see
## docs/protocol.md, Rates and limits.
static func parse_address(text: String, default_port: int = NetProtocol.DEFAULT_WS_PORT) -> Address:
	var r: Address = Address.new()
	var s: String = text.strip_edges()
	if s.is_empty():
		return r.fail("Enter the host's address, for example 192.168.1.20.")
	var scheme_at: int = s.find("://")
	if scheme_at >= 0:
		if s.substr(0, scheme_at).to_lower() != "ws":
			return r.fail("Enter the host's address or a ws:// address, not a web link.")
		s = s.substr(scheme_at + 3)
		if s.ends_with("/"):
			s = s.substr(0, s.length() - 1)
	if s.contains("/") or s.contains(" ") or s.contains("@"):
		return r.fail("That isn't a host address.")
	var h: String = s
	var port_text: String = ""
	if s.begins_with("["):
		var close: int = s.find("]")
		if close < 0:
			return r.fail("Missing ] after the IPv6 address.")
		h = s.substr(1, close - 1)
		var rest: String = s.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return r.fail("Unexpected text after the IPv6 address.")
			port_text = rest.substr(1)
		if not (h.contains(":") and h.is_valid_ip_address()):
			return r.fail("That isn't a valid IPv6 address.")
	elif s.count(":") == 1:
		h = s.get_slice(":", 0)
		port_text = s.get_slice(":", 1)
	elif s.count(":") > 1:
		if not s.is_valid_ip_address():
			return r.fail("That isn't a valid IPv6 address.")
	var reason: String = _host_problem(h)
	if not reason.is_empty():
		return r.fail(reason)
	var p: int = default_port
	if port_text != "" or s.ends_with(":"):
		if not port_text.is_valid_int() or port_text.begins_with("+"):
			return r.fail("The port must be a number from 1 to 65535.")
		p = port_text.to_int()
	if p < 1 or p > 65535:
		return r.fail("The port must be a number from 1 to 65535.")
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
