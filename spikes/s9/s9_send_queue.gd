class_name S9SendQueue
extends S4SendQueue
## S4SendQueue that also takes a ready-made single chunk, so one snapshot chunk
## (header and payload) is built once per view key and the same bytes are
## queued for every client holding that key (FT-NET-040). A single-chunk
## message's msg_id is never used for reassembly, so sharing it is safe.


func push_chunk(chunk: PackedByteArray) -> void:
	_high.append(chunk)
	high_bytes += chunk.size()
