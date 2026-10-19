class_name S4Chunker
extends RefCounted
## Splits a message into WebSocket packets of at most HEADER_SIZE + chunk_size bytes
## and reassembles them (FT-NET-038). Candidate for promotion to T045 (#6).
##
## Chunk header, little endian: stream u8, msg_id u32, index u16, count u16.
## Every message carries a header, also single-chunk ones, so the receiver has
## one code path. A message lives in one send lane, so its chunks arrive in order;
## chunks of different streams may interleave.

const HEADER_SIZE: int = 9
const DEFAULT_CHUNK_SIZE: int = 16384
const STREAM_CONTROL: int = 0
const STREAM_SNAPSHOT: int = 1
const STREAM_VOICE: int = 2

var errors: int = 0

## Partial messages: key (stream << 32 | msg_id) -> PackedByteArray so far.
var _partial: Dictionary = {}
## Next expected chunk index per key.
var _next_index: Dictionary = {}


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
## {"stream": int, "msg_id": int, "data": PackedByteArray}.
func feed(chunk: PackedByteArray) -> Dictionary:
	if chunk.size() < HEADER_SIZE:
		errors += 1
		return {}
	var stream: int = stream_of(chunk)
	var msg_id: int = msg_id_of(chunk)
	var index: int = index_of(chunk)
	var count: int = count_of(chunk)
	var payload: PackedByteArray = chunk.slice(HEADER_SIZE)
	if count == 1 and index == 0:
		return {"stream": stream, "msg_id": msg_id, "data": payload}
	var key: int = (stream << 32) | msg_id
	var expected: int = _next_index.get(key, 0)
	if index != expected:
		errors += 1
		_partial.erase(key)
		_next_index.erase(key)
		return {}
	if index == 0:
		_partial[key] = payload
	else:
		var sofar: PackedByteArray = _partial[key]
		sofar.append_array(payload)
		_partial[key] = sofar
	if index + 1 < count:
		_next_index[key] = index + 1
		return {}
	var data: PackedByteArray = _partial[key]
	_partial.erase(key)
	_next_index.erase(key)
	return {"stream": stream, "msg_id": msg_id, "data": data}


func pending_messages() -> int:
	return _partial.size()
