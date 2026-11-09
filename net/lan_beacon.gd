class_name LanBeacon
extends RefCounted
## Server side of LAN discovery (FT-NET-012, D70): broadcasts a small UDP datagram
## once a second so desktop clients on the LAN can list this server. No timer or
## Node: the server loop calls poll(now_usec). LAN only: there is no internet
## registration, relay or master server (FT-NET-031, FT-GEN-013).
##
## Datagram, little-endian like the game protocol, append-only (a newer format adds
## fields at the end, so a parser reads the fields it knows and ignores the rest):
##   0  4  magic "FTLB"
##   4  1  beacon format (FORMAT)
##   5  4  game protocol version (u32)
##   9  2  WebSocket port
##   11 2  HTTP port (static web export; D108: WS = HTTP + 1), 0 when HTTP is off
##   13 1  players connected
##   14 1  player cap
##   15 1  flags (bit 0: a session is active, NetServer.session_active())
##   16 1  server name length n (UTF-8 bytes, at most MAX_NAME_BYTES)
##   17 n  server name

## UDP discovery port, kept clear of the game's TCP ports to avoid confusion, though
## UDP and TCP don't clash. Port, interval and broadcast address are provisional: see
## docs/protocol.md, Rates and limits.
const DISCOVERY_PORT: int = 47790
const INTERVAL_USEC: int = 1_000_000
const MAGIC: PackedByteArray = [0x46, 0x54, 0x4C, 0x42]  # "FTLB"
const FORMAT: int = 1
const HEADER_BYTES: int = 17
const MAX_NAME_BYTES: int = 63
const FLAG_RUNNING: int = 1
## The limited broadcast address. It leaves by one interface only, so a multi-homed host
## (Wi-Fi plus Docker or Tailscale) also sends to each interface's subnet broadcast address
## (subnet_broadcasts, R11-7); destinations is overridable.
const BROADCAST_ADDRESS: String = "255.255.255.255"

var server_name: String
var protocol_version: int
var ws_port: int
var http_port: int
var players: int = 0
var player_cap: int = 64
## Flag bit 0: NetServer.session_active().
var session_running: bool = false
## Datagrams sent since start(), and the last put_packet error (OK if none).
var sent: int = 0
var last_error: Error = OK

var _peer: PacketPeerUDP
var _port: int = DISCOVERY_PORT
var _destinations: PackedStringArray = []
var _next_usec: int = -1


## p_http_port is 0 when the server doesn't serve the web export.
func _init(
	p_protocol_version: int, p_server_name: String, p_ws_port: int, p_http_port: int = 0
) -> void:
	protocol_version = p_protocol_version
	server_name = p_server_name
	ws_port = p_ws_port
	http_port = p_http_port


## Opens the sending socket; the error when the destinations are not addresses or the socket
## cannot open (last_error holds it too). With no `destinations` it sends to the limited
## broadcast address and the subnet broadcast of every local interface (default_destinations).
## Tests pass a loopback destination and their own port.
func start(
	port: int = DISCOVERY_PORT, destinations: PackedStringArray = PackedStringArray()
) -> Error:
	stop()
	_port = port
	_destinations = destinations if not destinations.is_empty() else default_destinations()
	for dest: String in _destinations:
		if not dest.is_valid_ip_address():
			last_error = ERR_INVALID_PARAMETER
			return last_error
	_peer = PacketPeerUDP.new()
	var err: Error = _peer.bind(0) as Error
	if err != OK:
		_peer = null
		last_error = err
		return err
	_peer.set_broadcast_enabled(true)
	_next_usec = -1
	sent = 0
	last_error = OK
	return OK


## The limited broadcast address and the subnet broadcast address of each local interface.
static func default_destinations() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([BROADCAST_ADDRESS])
	out.append_array(subnet_broadcasts(IP.get_local_interfaces()))
	return out


## The subnet broadcast address (a.b.c.255) of every usable IPv4 address in `interfaces`
## (IP.get_local_interfaces(): {name, addresses}), once each. Godot gives no netmask, so a
## /24 is assumed, the usual home or office LAN; loopback, link-local and unspecified
## addresses are skipped.
static func subnet_broadcasts(interfaces: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for iface: Dictionary in interfaces:
		for address: String in iface.get("addresses", []):
			var parts: PackedStringArray = address.split(".")
			if address.contains(":") or parts.size() != 4 or not address.is_valid_ip_address():
				continue
			if parts[0] in ["0", "127"] or (parts[0] == "169" and parts[1] == "254"):
				continue
			var broadcast: String = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if broadcast not in out:
				out.append(broadcast)
	return out


func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null


func is_running() -> bool:
	return _peer != null


## Sends a datagram on the first call and then once every INTERVAL_USEC. If the loop
## stalls, it sends once and restarts the interval rather than bursting. Returns true
## when it sent.
func poll(now_usec: int) -> bool:
	if _peer == null or (_next_usec >= 0 and now_usec < _next_usec):
		return false
	_next_usec = now_usec + INTERVAL_USEC
	var payload: PackedByteArray = encode()
	for dest: String in _destinations:
		_peer.set_dest_address(dest, _port)
		var err: Error = _peer.put_packet(payload) as Error
		if err != OK:
			last_error = err  # e.g. no network interface up; keep beaconing
	sent += 1
	return true


func encode() -> PackedByteArray:
	var name_bytes: PackedByteArray = _truncate_utf8(server_name, MAX_NAME_BYTES)
	var b: PackedByteArray = MAGIC.duplicate()
	b.resize(HEADER_BYTES)
	b[4] = FORMAT
	b.encode_u32(5, clampi(protocol_version, 0, 0xFFFFFFFF))
	b.encode_u16(9, clampi(ws_port, 0, 0xFFFF))
	b.encode_u16(11, clampi(http_port, 0, 0xFFFF))
	b[13] = clampi(players, 0, 255)
	b[14] = clampi(player_cap, 0, 255)
	b[15] = FLAG_RUNNING if session_running else 0
	b[16] = name_bytes.size()
	b.append_array(name_bytes)
	return b


## Parses a datagram. Returns {} for anything malformed or with the wrong magic, else
## {"format", "protocol", "ws_port", "http_port", "players", "cap", "running", "name"}.
static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() < HEADER_BYTES or b.slice(0, 4) != MAGIC:
		return {}
	var fmt: int = b[4]
	var n: int = b[16]
	if fmt < 1 or n > MAX_NAME_BYTES or b.size() < HEADER_BYTES + n:
		return {}
	var ws: int = b.decode_u16(9)
	if ws == 0:
		return {}
	return {
		"format": fmt,
		"protocol": b.decode_u32(5),
		"ws_port": ws,
		"http_port": b.decode_u16(11),
		"players": b[13],
		"cap": b[14],
		"running": (b[15] & FLAG_RUNNING) != 0,
		"name": b.slice(HEADER_BYTES, HEADER_BYTES + n).get_string_from_utf8(),
	}


## UTF-8 bytes of s, cut at a character boundary so they fit in max_bytes.
static func _truncate_utf8(s: String, max_bytes: int) -> PackedByteArray:
	var out: PackedByteArray = s.to_utf8_buffer()
	var i: int = s.length()
	while out.size() > max_bytes:
		i -= 1
		out = s.substr(0, i).to_utf8_buffer()
	return out
