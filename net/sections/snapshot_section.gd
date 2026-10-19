class_name SnapshotSection
extends RefCounted
## One section of the snapshot stream, encoded once per snapshot for its owner (a ship,
## or a faction for CONTACTS) and shared by every view key that lists it (FT-NET-040).
## The section keeps the model every client in its stream holds: update() advances the
## model to the snapshot and returns the delta bytes (empty: omit the section from the
## delta), full() serialises the model for a client that joins or resyncs. Deltas
## chain on the previous snapshot: TCP keeps order, and a client that misses one gets a
## full snapshot instead (FT-NET-037). NetViewState applies the bytes on the client.

var kind: int = 0
var owner: int = 0


func _init(section_kind: int, owner_id: int) -> void:
	kind = section_kind
	owner = owner_id


## Advances the model to the copied world's tick and returns the delta.
func update(_world: SimWorld) -> PackedByteArray:
	return PackedByteArray()


## The model as a full section at the last update's tick.
func full() -> PackedByteArray:
	return PackedByteArray()
