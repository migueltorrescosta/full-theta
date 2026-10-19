class_name LanBeacon
extends RefCounted
## Server side of LAN discovery (FT-NET-012, D70): broadcasts a small UDP datagram
## once a second so desktop clients on the LAN can list this server. No timer or
## Node: the server loop calls poll(now_usec). LAN only: there is no internet
## registration, relay or master server (FT-NET-031, FT-GEN-013).
##
## Datagram, big-endian, append-only (a newer format adds fields at the end, so a
## parser reads the fields it knows and ignores the rest):
##   0  4  magic "FTLB"
##   4  1  beacon format (FORMAT)
##   5  4  game protocol version (u32)
##   9  2  WebSocket port
##   11 2  HTTP port (static web export; D108: WS = HTTP + 1)
##   13 1  players connected
##   14 1  player cap
##   15 1  flags (bit 0: a session is running)
##   16 1  server name length n (UTF-8 bytes, at most MAX_NAME_BYTES)
##   17 n  server name

## Provisional: UDP discovery port, kept clear of the game's TCP ports (47800 and
## the HTTP port below it) to avoid confusion, though UDP and TCP don't clash.
const DISCOVERY_PORT: int = 47790
const INTERVAL_USEC: int = 1_000_000
const MAGIC: PackedByteArray = [0x46, 0x54, 0x4C, 0x42]  # "FTLB"
const FORMAT: int = 1
const HEADER_BYTES: int = 17
const MAX_NAME_BYTES: int = 63
const FLAG_RUNNING: int = 1
## Provisional: the limited broadcast address. A multi-homed host may need subnet
## broadcast addresses too (IP.get_local_interfaces()); destinations is overridable.
const BROADCAST_ADDRESS: String = "255.255.255.255"

var server_name: String
var protocol_version: int
var ws_port: int
var http_port: int
var players: int = 0
var player_cap: int = 64
var session_running: bool = false
## Datagrams sent since start(), and the last put_packet error (OK if none).
var sent: int = 0
var last_error: Error = OK

var _peer: PacketPeerUDP
var _port: int = DISCOVERY_PORT
var _destinations: PackedStringArray = []
var _next_usec: int = -1


## p_http_port < 0 means ws_port - 1 (D108).
func _init(
	p_protocol_version: int, p_server_name: String, p_ws_port: int, p_http_port: int = -1
) -> void:
	protocol_version = p_protocol_version
	server_name = p_server_name
	ws_port = p_ws_port
	http_port = p_http_port if p_http_port >= 0 else p_ws_port - 1


## Opens the sending socket. Tests pass a loopback destination and their own port.
func start(
	port: int = DISCOVERY_PORT, destinations: PackedStringArray = [BROADCAST_ADDRESS]
) -> Error:
	stop()
	_port = port
	_destinations = destinations
	_peer = PacketPeerUDP.new()
	_peer.set_broadcast_enabled(true)
	_next_usec = -1
	sent = 0
	return OK


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
	b.encode_u32(5, _be32(clampi(protocol_version, 0, 0xFFFFFFFF)))
	b.encode_u16(9, _be16(clampi(ws_port, 0, 0xFFFF)))
	b.encode_u16(11, _be16(clampi(http_port, 0, 0xFFFF)))
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
	var ws: int = _be16(b.decode_u16(9))
	if ws == 0:
		return {}
	return {
		"format": fmt,
		"protocol": _be32(b.decode_u32(5)),
		"ws_port": ws,
		"http_port": _be16(b.decode_u16(11)),
		"players": b[13],
		"cap": b[14],
		"running": (b[15] & FLAG_RUNNING) != 0,
		"name": b.slice(HEADER_BYTES, HEADER_BYTES + n).get_string_from_utf8(),
	}


## Byte swaps, so the wire is big-endian whatever the host order
## (PackedByteArray.encode_* is little-endian).
static func _be16(v: int) -> int:
	return ((v & 0xFF) << 8) | ((v >> 8) & 0xFF)


static func _be32(v: int) -> int:
	return (
		((v & 0xFF) << 24)
		| (((v >> 8) & 0xFF) << 16)
		| (((v >> 16) & 0xFF) << 8)
		| ((v >> 24) & 0xFF)
	)


## UTF-8 bytes of s, cut at a character boundary so they fit in max_bytes.
static func _truncate_utf8(s: String, max_bytes: int) -> PackedByteArray:
	var out: PackedByteArray = s.to_utf8_buffer()
	var i: int = s.length()
	while out.size() > max_bytes:
		i -= 1
		out = s.substr(0, i).to_utf8_buffer()
	return out
