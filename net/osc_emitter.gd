class_name OscEmitter
extends RefCounted
## Room hardware events (FT-NET-047, D470, D471): sends each crewed ship's hits, jumps,
## destruction and alert level as OSC 1.0 messages over UDP to the LAN addresses the host
## lists (`--osc`), for QLC+, Node-RED or an Arduino. Outbound only: it never reads a
## packet, so nothing listens. Off unless the host gives targets. Addresses and arguments
## are in docs/launch.md ("Room hardware").

## Most targets one server sends to.
const MAX_TARGETS: int = 8
## A ship's hits are sent at most this often (s); the hits in between are dropped (D471).
## The other messages are rare state changes and always go.
const HIT_INTERVAL: float = 0.1
## Address prefix: /ft/ship/<ship id>/<event>.
const PREFIX: String = "/ft/ship/"

## Datagrams sent (a failed send is dropped: UDP gives no delivery anyway).
var sent: int = 0
## "ip:port" per target, as given.
var _targets: Array[Array] = []
var _peer: PacketPeerUDP = PacketPeerUDP.new()
## Ship -> when its last hit went (us).
var _last_hit_us: Dictionary[int, int] = {}
## Ship -> the alert level last sent.
var _alert: Dictionary[int, int] = {}


## An emitter for "ip:port,ip:port", or null with the problem pushed as an error.
static func from_list(list: String) -> OscEmitter:
	var e: OscEmitter = OscEmitter.new()
	var why: String = e.set_targets(list)
	if why != "":
		push_error("--osc: %s" % why)
		return null
	return e


## Parses the targets; returns why they are refused, or "".
func set_targets(list: String) -> String:
	_targets.clear()
	for item: String in list.split(",", false):
		var parts: PackedStringArray = item.strip_edges().rsplit(":", true, 1)
		if parts.size() != 2 or not parts[1].is_valid_int():
			return "%s: expected IPv4:PORT" % item
		var port: int = parts[1].to_int()
		if port < 1 or port > 65535:
			return "%s: port must be 1..65535" % item
		if not is_lan(parts[0]):
			return "%s: not a LAN address (10/8, 172.16/12, 192.168/16, 169.254/16, 127/8)" % item
		_targets.append([parts[0], port])
	if _targets.is_empty():
		return "no targets"
	if _targets.size() > MAX_TARGETS:
		return "at most %d targets" % MAX_TARGETS
	return ""


## True for a private, link-local or loopback IPv4 address: the room's own network.
static func is_lan(ip: String) -> bool:
	var o: PackedStringArray = ip.split(".")
	if o.size() != 4:
		return false
	var b: PackedInt32Array = PackedInt32Array()
	for part: String in o:
		if not part.is_valid_int() or part.to_int() < 0 or part.to_int() > 255:
			return false
		b.append(part.to_int())
	return (
		b[0] == 10
		or b[0] == 127
		or (b[0] == 172 and b[1] >= 16 and b[1] <= 31)
		or (b[0] == 192 and b[1] == 168)
		or (b[0] == 169 and b[1] == 254)
	)


## Sends the messages for one frame's sim events and alert levels. `crew` holds the crewed
## ship ids; `alert_of` maps a ship to its alert level (0 Normal, 1 Yellow, 2 Red).
func after_ticks(
	events: Array[SimEvent], crew: PackedInt32Array, alert_of: Callable, now_us: int
) -> void:
	for e: SimEvent in events:
		if crew.has(e.ship_id):
			for m: Array in messages_for(e, now_us):
				send(m[0], m[1])
	for ship: int in crew:
		var level: int = alert_of.call(ship)
		if _alert.get(ship, 0) != level:
			_alert[ship] = level
			send(PREFIX + "%d/alert" % ship, [level / 2.0, level])


## The [address, args] messages one event of a crewed ship makes (rate limit applied).
func messages_for(e: SimEvent, now_us: int) -> Array[Array]:
	var at: String = PREFIX + "%d/" % e.ship_id
	match e.kind:
		&"hit":
			var last_us: int = _last_hit_us.get(e.ship_id, -(1 << 62))
			if now_us - last_us < HIT_INTERVAL * 1e6:
				return []
			_last_hit_us[e.ship_id] = now_us
			return [[at + "hit", [1.0, e.value]]]
		&"jump_spool":
			return [[at + "jump", [1.0]]]
		&"jump_arrive":
			return [[at + "jump", [0.0]]]
		&"destroyed":
			return [[at + "destroyed", [1.0]]]
	return []


## Sends one message to every target.
func send(address: String, args: Array) -> void:
	var packet: PackedByteArray = encode(address, args)
	for t: Array in _targets:
		_peer.set_dest_address(t[0], t[1])
		if _peer.put_packet(packet) == OK:
			sent += 1


## One OSC 1.0 message: the address, the type tags and the arguments, each padded to 4
## bytes, numbers big-endian. Floats go as f (float32), ints as i (int32).
static func encode(address: String, args: Array) -> PackedByteArray:
	var tags: String = ","
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.big_endian = true
	for a: Variant in args:
		if a is int:
			tags += "i"
			body.put_32(a)
		else:
			tags += "f"
			body.put_float(float(a))
	var out: PackedByteArray = _padded(address)
	out.append_array(_padded(tags))
	out.append_array(body.data_array)
	return out


## An OSC string: ASCII, at least one NUL, padded to a multiple of 4 bytes.
static func _padded(s: String) -> PackedByteArray:
	var b: PackedByteArray = s.to_ascii_buffer()
	b.append(0)
	while b.size() % 4 != 0:
		b.append(0)
	return b
