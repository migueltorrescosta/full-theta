class_name NetSendQueue
extends RefCounted
## Per-connection send queue with two lanes (FT-NET-038; promoted from S4SendQueue and
## S9SendQueue). The high lane (control, events, snapshots) is FIFO, so events and
## snapshots keep their order. The low lane holds voice chunks and is served only when
## the high lane is empty, at most low_per_pump chunks per pump, so a voice clip never
## sits in front of a snapshot by more than the chunks already handed to the socket.
## take_bundle() packs the chunks one pump may send into one WebSocket message.

var chunk_size: int = NetChunker.DEFAULT_CHUNK_SIZE
var low_per_pump: int = 1
var high_bytes: int = 0
var low_bytes: int = 0

var _high: Array[PackedByteArray] = []
var _low: Array[PackedByteArray] = []
var _next_msg_id: int = 1
var _low_sent_this_pump: int = 0


func _init(size: int = NetChunker.DEFAULT_CHUNK_SIZE, low_chunks_per_pump: int = 1) -> void:
	chunk_size = size
	low_per_pump = low_chunks_per_pump


## Queues a message on the lane of its stream; returns its msg_id.
func push(stream: int, data: PackedByteArray) -> int:
	var msg_id: int = _next_msg_id
	_next_msg_id = (_next_msg_id + 1) & 0xFFFFFFFF
	for chunk: PackedByteArray in NetChunker.split(stream, msg_id, data, chunk_size):
		if stream == NetChunker.STREAM_VOICE:
			_low.append(chunk)
			low_bytes += chunk.size()
		else:
			_high.append(chunk)
			high_bytes += chunk.size()
	return msg_id


## Queues ready-made chunks of a message on the high lane, as built once per view key
## and shared by every client holding that key (FT-NET-040). The receiver keeps one
## partial message per stream and the chunks stay contiguous, so a shared msg_id is
## safe.
func push_chunks(chunks: Array[PackedByteArray]) -> void:
	for chunk: PackedByteArray in chunks:
		_high.append(chunk)
		high_bytes += chunk.size()


## Starts a send pass: resets the per-pump low-lane budget.
func begin_pump() -> void:
	_low_sent_this_pump = 0


## Size of the chunk next_chunk() would return, or 0 if none may go now.
func peek_size() -> int:
	if not _high.is_empty():
		return _high[0].size()
	if not _low.is_empty() and _low_sent_this_pump < low_per_pump:
		return _low[0].size()
	return 0


## Next chunk to hand to the socket this pump, or an empty array.
func next_chunk() -> PackedByteArray:
	if not _high.is_empty():
		var chunk: PackedByteArray = _high.pop_front()
		high_bytes -= chunk.size()
		return chunk
	if not _low.is_empty() and _low_sent_this_pump < low_per_pump:
		var chunk: PackedByteArray = _low.pop_front()
		low_bytes -= chunk.size()
		_low_sent_this_pump += 1
		return chunk
	return PackedByteArray()


## The chunks this pump may send, concatenated into one bundle of at most max_bytes
## (always at least one chunk if any may go); empty if none may go.
func take_bundle(max_bytes: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	while true:
		var size: int = peek_size()
		if size == 0 or (not out.is_empty() and out.size() + size > max_bytes):
			break
		out.append_array(next_chunk())
	return out


func is_empty() -> bool:
	return _high.is_empty() and _low.is_empty()
