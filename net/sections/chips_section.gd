class_name ChipsSection
extends SnapshotSection
## Section.CHIPS: the open request chips of one ship (NetChips on the server's main thread
## posts them, NetTransport.post_chips). A crew view lists the chips it sends or receives;
## the Captain, the Viewer and the dev entry list all of them (ViewFilter). Sent whole when
## the list changes, like a block.

## The ship's open chips as last posted (set by SnapshotBuilder before update()).
var rows: Array = []
var filter: ViewFilter = null
var _last: PackedByteArray = PackedByteArray()


func _init(section_kind: int, owner_id: int, view_filter: ViewFilter = null) -> void:
	super(section_kind, owner_id)
	filter = view_filter


func update(_world: SimWorld) -> PackedByteArray:
	var mine: Array = []
	for row: Dictionary in rows:
		if filter == null or filter.sees_all or _involves(row):
			mine.append(row)
	var bytes: PackedByteArray = NetBlock.encode(
		StationViews.BLOCKS[StationViews.Section.CHIPS], {"chips": mine}
	)
	if bytes == _last:
		return PackedByteArray()
	_last = bytes
	return bytes


func full() -> PackedByteArray:
	return _last


func _involves(row: Dictionary) -> bool:
	return (
		filter.stations.has(StationViews.CREW[row["from"]])
		or filter.stations.has(StationViews.CREW[row["to"]])
	)
