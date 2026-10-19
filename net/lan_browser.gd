class_name LanBrowser
extends RefCounted
## Client side of LAN discovery (FT-NET-012, FT-NET-013): listens for LanBeacon
## datagrams and keeps the list of hosts seen in the last EXPIRY_USEC. No timer or
## Node: the client calls poll(now_usec) each frame.
##
## One listener per machine: Godot 4.7's PacketPeerUDP doesn't set SO_REUSEADDR, so
## a second client on the same machine gets an error from start() (checked on
## fugaku). That client still joins by manual address (JoinAddress), e.g. the
## host's own client, which joins its server on localhost anyway (FT-NET-001).


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
		return JoinAddress.ws_url(address, ws_port)


## Hosts silent for longer than this are dropped (3.5 beacon intervals).
const EXPIRY_USEC: int = 3_500_000
const MAX_PACKETS_PER_POLL: int = 64

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
