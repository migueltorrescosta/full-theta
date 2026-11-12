class_name SnapshotSection
extends RefCounted
## One section of the snapshot stream, encoded once per snapshot for its owner (a ship,
## or a faction for CONTACTS) and shared by every stream key that lists it (FT-NET-040).
## The section keeps the model every client in its stream holds: update() advances the
## model to the snapshot and returns the delta bytes (empty: omit the section from the
## delta), full() serialises the model for a client that joins or resyncs. Deltas
## chain on the previous snapshot: TCP keeps order, and a client that misses one gets a
## full snapshot instead (FT-NET-037). SnapshotState applies the bytes on the client.

var kind: int = 0
var owner: int = 0
## The last bytes sent, for the sections that send their whole state when it changes.
var _last: PackedByteArray = PackedByteArray()


func _init(section_kind: int, owner_id: int) -> void:
	kind = section_kind
	owner = owner_id


## Advances the model to the copied world's tick and returns the delta.
func update(_world: SimWorld) -> PackedByteArray:
	return PackedByteArray()


## The model as a full section at the last update's tick: by default the last bytes sent.
func full() -> PackedByteArray:
	return _last


## The dedupe tail of a whole-state section (R06-7): the bytes when they changed (and they
## become the full section), else empty, which omits the section from the delta.
func _changed(bytes: PackedByteArray) -> PackedByteArray:
	if bytes == _last:
		return PackedByteArray()
	_last = bytes
	return bytes
