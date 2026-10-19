class_name BlockSection
extends SnapshotSection
## A per-ship block of fields (Section.STATUS, HELM, ENGINEERING, MOUNTS) whose field
## set is StationViews.BLOCKS[kind]. Sent whole when any field's encoding changed, else
## omitted from the delta.

var _last: PackedByteArray = PackedByteArray()


func update(world: SimWorld) -> PackedByteArray:
	var bytes: PackedByteArray = StationViews.block_bytes(kind, world, owner)
	if bytes == _last:
		return PackedByteArray()
	_last = bytes
	return bytes


func full() -> PackedByteArray:
	return _last
