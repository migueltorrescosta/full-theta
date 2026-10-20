class_name S4Chunker
extends RefCounted
## Splits a message into WebSocket packets of at most HEADER_SIZE + chunk_size bytes
## and reassembles them (FT-NET-038). Candidate for promotion to T045 (#6).
##
## Chunk header, little endian: stream u8, msg_id u32, index u16, count u16.
## Every message carries a header, also single-chunk ones, so the receiver has
## one code path. A sender queues all chunks of a message together in one lane,
## so per stream they arrive contiguously and in order; chunks of different
## streams may interleave. The receiver therefore holds at most one partial
## message per stream and drops it when another message starts on that stream.

const HEADER_SIZE: int = 9
const DEFAULT_CHUNK_SIZE: int = 16384
const STREAM_CONTROL: int = 0
const STREAM_SNAPSHOT: int = 1
const STREAM_VOICE: int = 2

## Largest message accepted, as `WebSocketPeer.encode_buffer_max_size` (8 MiB).
const MAX_MESSAGE_SIZE: int = 8 * 1024 * 1024

## Malformed or dropped chunks seen so far.
var errors: int = 0

## Partial message per stream: stream -> [msg_id, count, next_index, data so far].
var _partial: Dictionary = {}


static func split(
	stream: int, msg_id: int, data: PackedByteArray, chunk_size: int
) -> Array[PackedByteArray]:
	var count: int = maxi(1, ceili(float(data.size()) / chunk_size))
	var out: Array[PackedByteArray] = []
	for i: int in range(count):
		var chunk: PackedByteArray = PackedByteArray()
		chunk.resize(HEADER_SIZE)
		chunk.encode_u8(0, stream)
		chunk.encode_u32(1, msg_id)
		chunk.encode_u16(5, i)
		chunk.encode_u16(7, count)
		chunk.append_array(data.slice(i * chunk_size, mini((i + 1) * chunk_size, data.size())))
		out.append(chunk)
	return out


static func stream_of(chunk: PackedByteArray) -> int:
	return chunk.decode_u8(0)


static func msg_id_of(chunk: PackedByteArray) -> int:
	return chunk.decode_u32(1)


static func index_of(chunk: PackedByteArray) -> int:
	return chunk.decode_u16(5)


static func count_of(chunk: PackedByteArray) -> int:
	return chunk.decode_u16(7)


## Feeds one received packet. Returns {} until a message is complete, then
## {"stream": int, "msg_id": int, "data": PackedByteArray}. A malformed chunk
## (short header, count 0, index out of range or out of order, a count that
## changes mid-message, a message over MAX_MESSAGE_SIZE) counts as an error and
## drops the stream's partial message.
func feed(chunk: PackedByteArray) -> Dictionary:
	if chunk.size() < HEADER_SIZE:
		errors += 1
		return {}
	var stream: int = stream_of(chunk)
	var msg_id: int = msg_id_of(chunk)
	var index: int = index_of(chunk)
	var count: int = count_of(chunk)
	var part: Array = _partial.get(stream, [])
	_partial.erase(stream)
	if not part.is_empty() and int(part[0]) != msg_id:
		# Another message started before this one finished: it never will.
		errors += 1
		part = []
	var expected: int = 0 if part.is_empty() else int(part[2])
	if count == 0 or index >= count or index != expected:
		errors += 1
		return {}
	if not part.is_empty() and int(part[1]) != count:
		errors += 1
		return {}
	var data: PackedByteArray = PackedByteArray() if part.is_empty() else part[3]
	part.clear()
	data.append_array(chunk.slice(HEADER_SIZE))
	if data.size() > MAX_MESSAGE_SIZE:
		errors += 1
		return {}
	if index + 1 < count:
		_partial[stream] = [msg_id, count, index + 1, data]
		return {}
	return {"stream": stream, "msg_id": msg_id, "data": data}


func pending_messages() -> int:
	return _partial.size()
