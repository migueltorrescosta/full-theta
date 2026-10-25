class_name BlockSection
extends SnapshotSection
## A per-ship block of fields (Section.STATUS, HELM, ENGINEERING, MOUNTS) whose field
## set is StationViews.BLOCKS[kind]. Sent whole when any field's encoding changed, else
## omitted from the delta.

## What the section's view may carry of other stations' data, or null for everything
## (ViewFilter; sections of a filtered kind exist once per filter signature).
var filter: ViewFilter = null
var _last: PackedByteArray = PackedByteArray()


func _init(section_kind: int, owner_id: int, view_filter: ViewFilter = null) -> void:
	super(section_kind, owner_id)
	filter = view_filter


func update(world: SimWorld) -> PackedByteArray:
	var bytes: PackedByteArray = StationViews.block_bytes(kind, world, owner, filter)
	if bytes == _last:
		return PackedByteArray()
	_last = bytes
	return bytes


func full() -> PackedByteArray:
	return _last
