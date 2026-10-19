class_name NetChunker
extends RefCounted
## Splits messages into chunks of at most chunk_size payload bytes and reassembles
## them (FT-NET-038; promoted from S4Chunker). Several chunks travel in one WebSocket
## message (a bundle), so a pump writes one message per client however many chunks it
## sends (see docs/protocol.md, "Packets per message").
##
## Chunk header, little endian: stream u8, msg_id u32, index u16, count u16, length
## u16 (payload bytes in this chunk). Every message has a header, single-chunk ones
## too. A sender queues all chunks of a message together in one lane, so per stream
## they arrive contiguously and in order; chunks of different streams may interleave.
## The receiver holds at most one partial message per stream and drops it when another
## message starts on that stream.

const HEADER_SIZE: int = 11
const DEFAULT_CHUNK_SIZE: int = 16384
const STREAM_CONTROL: int = 0
const STREAM_SNAPSHOT: int = 1
const STREAM_VOICE: int = 2
## Largest message accepted, as `WebSocketPeer.encode_buffer_max_size` (8 MiB).
const MAX_MESSAGE_SIZE: int = 8 * 1024 * 1024

## Largest message this receiver reassembles; the server lowers it for clients
## (NetTransport.MAX_CLIENT_MESSAGE).
var max_message_size: int = MAX_MESSAGE_SIZE
## Malformed or dropped chunks seen so far.
var errors: int = 0

## Partial message per stream: stream -> [msg_id, count, next_index, data so far].
var _partial: Dictionary = {}


static func split(
	stream: int, msg_id: int, data: PackedByteArray, chunk_size: int = DEFAULT_CHUNK_SIZE
) -> Array[PackedByteArray]:
	var count: int = maxi(1, ceili(float(data.size()) / chunk_size))
	var out: Array[PackedByteArray] = []
	for i: int in range(count):
		var part: PackedByteArray = data.slice(
			i * chunk_size, mini((i + 1) * chunk_size, data.size())
		)
		var chunk: PackedByteArray = PackedByteArray()
		chunk.resize(HEADER_SIZE)
		chunk.encode_u8(0, stream)
		chunk.encode_u32(1, msg_id)
		chunk.encode_u16(5, i)
		chunk.encode_u16(7, count)
		chunk.encode_u16(9, part.size())
		chunk.append_array(part)
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


## Splits a received WebSocket message (a bundle of whole chunks) into its chunks; a
## truncated bundle counts as an error and yields the chunks before the damage.
func unbundle(packet: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var pos: int = 0
	while pos < packet.size():
		if packet.size() - pos < HEADER_SIZE:
			errors += 1
			break
		var size: int = HEADER_SIZE + packet.decode_u16(pos + 9)
		if pos + size > packet.size():
			errors += 1
			break
		out.append(packet.slice(pos, pos + size))
		pos += size
	return out


## Feeds one received WebSocket message; returns the messages it completes, each
## {"stream": int, "msg_id": int, "data": PackedByteArray}.
func feed_packet(packet: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chunk: PackedByteArray in unbundle(packet):
		var msg: Dictionary = feed(chunk)
		if not msg.is_empty():
			out.append(msg)
	return out


## Feeds one chunk. Returns {} until a message is complete, then {"stream", "msg_id",
## "data"}. A malformed chunk (short header, a length that disagrees with the chunk,
## count 0, index out of range or out of order, a count that changes mid-message, a
## message over max_message_size) counts as an error and drops the stream's partial
## message.
func feed(chunk: PackedByteArray) -> Dictionary:
	if chunk.size() < HEADER_SIZE or chunk.decode_u16(9) != chunk.size() - HEADER_SIZE:
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
	if data.size() > max_message_size:
		errors += 1
		return {}
	if index + 1 < count:
		_partial[stream] = [msg_id, count, index + 1, data]
		return {}
	return {"stream": stream, "msg_id": msg_id, "data": data}


func pending_messages() -> int:
	return _partial.size()
