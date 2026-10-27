class_name CommsSection
extends SnapshotSection
## Section.COMMS: Comms' card board of one ship (CommsView). Like a block it is sent whole
## when any field changed, else omitted from the delta. It reads the ship's claims
## (`npc:<card>` items, the main thread's OwnershipSection data) to name each conversation's
## claimer, so a claim change is a change here too.

## The ship's claims as last posted, item -> [session id, name] (SnapshotBuilder sets it
## before update()).
var claims: Dictionary = {}
var filter: ViewFilter = null
var _last: PackedByteArray = PackedByteArray()


func _init(section_kind: int, owner_id: int, view_filter: ViewFilter = null) -> void:
	super(section_kind, owner_id)
	filter = view_filter


func update(world: SimWorld) -> PackedByteArray:
	var bytes: PackedByteArray = NetBlock.encode(
		StationViews.BLOCKS[StationViews.Section.COMMS],
		CommsView.block(world, owner, filter, claims)
	)
	if bytes == _last:
		return PackedByteArray()
	_last = bytes
	return bytes


func full() -> PackedByteArray:
	return _last
