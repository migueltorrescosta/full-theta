class_name OwnershipSection
extends SnapshotSection
## Who holds what on one ship (Section.OWNERSHIP): the claimer of each claimed item
## (FT-NET-023) and the last writer of each ship-wide control (FT-NET-044). The main
## thread owns claims (ServerSession) and posts the ship's table to the net thread
## whenever it changes (NetTransport.post_ownership); each view key gets only its own
## stations' items (StationViews.ownership_for), so the section is filtered per entry,
## not shared whole like the other per-ship sections. Sent whole on change.
##
## Payload: var_to_bytes of {"claims": {item: [session id, name]}, "writers": {control:
## [session id, name]}} (rare, small; decoded with bytes_to_var, which builds no
## objects).

## The ship's table as last posted (set by SnapshotBuilder before update()).
var data: Dictionary = {}
var _sent: Dictionary = {}


func update(_world: SimWorld) -> PackedByteArray:
	if data == _sent:
		return PackedByteArray()
	_sent = data.duplicate(true)
	# A marker: SnapshotBuilder encodes the per-entry payload (for_entry).
	return PackedByteArray([1])


## The section bytes an entry sees.
func for_entry(entry: String) -> PackedByteArray:
	return var_to_bytes(StationViews.ownership_for(entry, _sent))


## Client side: the decoded table, or {} if malformed.
static func read(part: PackedByteArray) -> Dictionary:
	var v: Variant = bytes_to_var(part)
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	if not (d.get("claims") is Dictionary and d.get("writers") is Dictionary):
		return {}
	return d
