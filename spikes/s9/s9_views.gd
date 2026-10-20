class_name S9Views
extends RefCounted
## S9 view keys and snapshot framing (FT-NET-008, FT-NET-028, FT-NET-040).
##
## A view key is (ship, catalogue entry, difficulty-toggle set). Each catalogue
## entry maps to a list of sections; each section is encoded once per snapshot
## per owner (ship or faction), and each view key's message is assembled once
## per snapshot from them and shared by every client holding that key.
##
## Snapshot message: u8 type (1), u8 flags (bit 0 full), u32 seq, u32 tick,
## s64 sent_us (the age probe; a game build would drop it), u8 n, then n
## sections of u8 kind, u16 length, payload.

const MSG_SNAPSHOT: int = 1
const MSG_ACK: int = 2
const HEADER_BYTES: int = 19
const CREW_ENTRIES: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const VIEWER: String = "viewer"
## Provisional field sets: every station shows the disc radar (FT-STN-002);
## the views that draw ship models and tracers (Helm cockpit, Weapons turret,
## main screen, FT-MSC-001) add near orientations and projectiles; only
## Engineering gets the subsystem table.
const SECTIONS: Dictionary = {
	"helm": [S9Own.KIND_OWN, S9Radar.KIND, S9Near.KIND, S9Proj.KIND],
	"weapons": [S9Own.KIND_OWN, S9Radar.KIND, S9Near.KIND, S9Proj.KIND],
	"engineering": [S9Own.KIND_OWN, S9Own.KIND_ENG, S9Radar.KIND],
	"science": [S9Own.KIND_OWN, S9Radar.KIND],
	"relay": [S9Own.KIND_OWN, S9Radar.KIND],
	"comms": [S9Own.KIND_OWN, S9Radar.KIND],
	"viewer": [S9Own.KIND_OWN, S9Radar.KIND, S9Near.KIND, S9Proj.KIND],
}


static func key(ship: int, entry: String, toggles: String) -> String:
	return "%d|%s|%s" % [ship, entry, toggles]


## Seat for the index-th simulated connection: the first ships * 6 are crew,
## one per station of each ship; the rest are viewers dealt round the ships.
static func seat_for(index: int, ships: int) -> Dictionary:
	var crew: int = ships * CREW_ENTRIES.size()
	if index < crew:
		return {
			"ship": index / CREW_ENTRIES.size(),
			"entry": CREW_ENTRIES[index % CREW_ENTRIES.size()],
		}
	return {"ship": (index - crew) % ships, "entry": VIEWER}


static func message(
	seq: int, tick: int, sent_us: int, is_full: bool, kinds: Array, parts: Array[PackedByteArray]
) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(MSG_SNAPSHOT)
	buf.put_u8(1 if is_full else 0)
	buf.put_u32(seq)
	buf.put_u32(tick)
	buf.put_64(sent_us)
	buf.put_u8(parts.size())
	for i: int in range(parts.size()):
		buf.put_u8(kinds[i])
		buf.put_u16(parts[i].size())
		buf.put_data(parts[i])
	return buf.data_array


static func ack(seq: int) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(MSG_ACK)
	buf.put_u32(seq)
	return buf.data_array


## Header fields without decoding the sections: [seq, full, tick, sent_us].
static func peek(data: PackedByteArray) -> Array:
	return [data.decode_u32(2), data[1] & 1 == 1, data.decode_u32(6), data.decode_s64(10)]
