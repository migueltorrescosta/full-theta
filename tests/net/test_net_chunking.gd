extends GdUnitTestSuite
## Chunker, bundles and the two-lane send queue (promoted from the S4 spike tests).
# FT: FT-NET-038


func _bytes(size: int, value: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(size)
	data.fill(value)
	return data


func test_split_sizes_and_headers() -> void:
	var chunks: Array[PackedByteArray] = NetChunker.split(2, 77, _bytes(40000, 1), 16384)
	assert_int(chunks.size()).is_equal(3)
	assert_int(chunks[0].size()).is_equal(NetChunker.HEADER_SIZE + 16384)
	assert_int(chunks[2].size()).is_equal(NetChunker.HEADER_SIZE + 40000 - 2 * 16384)
	assert_int(NetChunker.stream_of(chunks[1])).is_equal(2)
	assert_int(NetChunker.msg_id_of(chunks[1])).is_equal(77)
	assert_int(NetChunker.index_of(chunks[1])).is_equal(1)
	assert_int(NetChunker.count_of(chunks[1])).is_equal(3)


func test_empty_message_is_one_chunk() -> void:
	var chunks: Array[PackedByteArray] = NetChunker.split(0, 1, PackedByteArray(), 16384)
	assert_int(chunks.size()).is_equal(1)
	var msg: Dictionary = NetChunker.new().feed(chunks[0])
	assert_int((msg["data"] as PackedByteArray).size()).is_equal(0)


func test_interleaved_streams_reassemble() -> void:
	var voice: PackedByteArray = _bytes(132440, 7)
	var snap: PackedByteArray = var_to_bytes({"seq": 5, "pad": _bytes(70000, 3)})
	var v: Array[PackedByteArray] = NetChunker.split(NetChunker.STREAM_VOICE, 1, voice, 16384)
	var s: Array[PackedByteArray] = NetChunker.split(NetChunker.STREAM_SNAPSHOT, 2, snap, 16384)
	var r: NetChunker = NetChunker.new()
	var mixed: Array[PackedByteArray] = []
	for i: int in range(v.size()):
		mixed.append(v[i])
		if i < s.size():
			mixed.append(s[i])
	var done: Array[Dictionary] = []
	for chunk: PackedByteArray in mixed:
		var msg: Dictionary = r.feed(chunk)
		if not msg.is_empty():
			done.append(msg)
	assert_int(done.size()).is_equal(2)
	assert_int(done[0]["stream"]).is_equal(NetChunker.STREAM_SNAPSHOT)
	assert_bool(done[0]["data"] == snap).is_true()
	assert_bool(done[1]["data"] == voice).is_true()
	assert_int(r.errors).is_equal(0)
	assert_int(r.pending_messages()).is_equal(0)


func test_out_of_order_chunk_is_an_error() -> void:
	var c: Array[PackedByteArray] = NetChunker.split(1, 9, _bytes(40000, 1), 16384)
	var r: NetChunker = NetChunker.new()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_bool(r.feed(c[2]).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)


func _chunk(stream: int, msg_id: int, index: int, count: int, size: int) -> PackedByteArray:
	var chunk: PackedByteArray = PackedByteArray()
	chunk.resize(NetChunker.HEADER_SIZE)
	chunk.encode_u8(0, stream)
	chunk.encode_u32(1, msg_id)
	chunk.encode_u16(5, index)
	chunk.encode_u16(7, count)
	chunk.encode_u16(9, size)
	chunk.append_array(_bytes(size, 5))
	return chunk


func test_duplicate_chunk_drops_the_message() -> void:
	var c: Array[PackedByteArray] = NetChunker.split(1, 9, _bytes(40000, 1), 16384)
	var r: NetChunker = NetChunker.new()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)
	assert_int(r.pending_messages()).is_equal(0)
	# The rest of the message can't complete it any more.
	assert_bool(r.feed(c[1]).is_empty()).is_true()
	assert_bool(r.feed(c[2]).is_empty()).is_true()
	assert_int(r.pending_messages()).is_equal(0)
	# A later message on the stream still arrives.
	var next: Array[PackedByteArray] = NetChunker.split(1, 10, _bytes(100, 2), 16384)
	assert_bool(r.feed(next[0]).is_empty()).is_false()


func test_malformed_chunks_are_rejected() -> void:
	var r: NetChunker = NetChunker.new()
	assert_bool(r.feed(PackedByteArray([1, 2, 3])).is_empty()).is_true()
	assert_bool(r.feed(_chunk(0, 1, 0, 0, 10)).is_empty()).is_true()
	assert_bool(r.feed(_chunk(0, 2, 3, 3, 10)).is_empty()).is_true()
	assert_bool(r.feed(_chunk(0, 3, 1, 3, 10)).is_empty()).is_true()
	assert_int(r.errors).is_equal(4)
	assert_int(r.pending_messages()).is_equal(0)
	# The count changes mid-message.
	assert_bool(r.feed(_chunk(0, 4, 0, 3, 10)).is_empty()).is_true()
	assert_bool(r.feed(_chunk(0, 4, 1, 2, 10)).is_empty()).is_true()
	assert_int(r.errors).is_equal(5)
	assert_int(r.pending_messages()).is_equal(0)


func test_new_message_replaces_unfinished_partial() -> void:
	var r: NetChunker = NetChunker.new()
	for id: int in range(1, 100):
		assert_bool(r.feed(_chunk(1, id, 0, 2, 10)).is_empty()).is_true()
	assert_int(r.pending_messages()).is_equal(1)
	assert_int(r.errors).is_equal(98)
	var msg: Dictionary = r.feed(_chunk(1, 99, 1, 2, 10))
	assert_int(msg["msg_id"]).is_equal(99)
	assert_int((msg["data"] as PackedByteArray).size()).is_equal(20)
	assert_int(r.pending_messages()).is_equal(0)


func test_message_over_the_size_cap_is_rejected() -> void:
	var r: NetChunker = NetChunker.new()
	var size: int = 60000
	var count: int = NetChunker.MAX_MESSAGE_SIZE / size + 1
	# (60,000-byte chunks: larger than the default chunk size, still valid on receive.)
	for i: int in range(count - 1):
		assert_bool(r.feed(_chunk(2, 7, i, count, size)).is_empty()).is_true()
	assert_int(r.errors).is_equal(0)
	assert_int(r.pending_messages()).is_equal(1)
	assert_bool(r.feed(_chunk(2, 7, count - 1, count, size)).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)
	assert_int(r.pending_messages()).is_equal(0)


# The server lowers the cap for client messages (NetTransport.MAX_CLIENT_MESSAGE).
func test_lowered_size_cap() -> void:
	var r: NetChunker = NetChunker.new()
	r.max_message_size = 100
	assert_bool(r.feed(_chunk(0, 1, 0, 1, 100)).is_empty()).is_false()
	assert_bool(r.feed(_chunk(0, 2, 0, 2, 60)).is_empty()).is_true()
	assert_bool(r.feed(_chunk(0, 2, 1, 2, 60)).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)


func test_snapshot_chunks_go_before_earlier_voice() -> void:
	var q: NetSendQueue = NetSendQueue.new(16384, 1)
	q.push(NetChunker.STREAM_VOICE, _bytes(132440, 7))
	q.push(NetChunker.STREAM_SNAPSHOT, _bytes(70000, 3))
	q.begin_pump()
	var order: Array[int] = []
	while q.peek_size() > 0:
		order.append(NetChunker.stream_of(q.next_chunk()))
	# Five snapshot chunks, then only one voice chunk this pump.
	assert_array(order).is_equal([1, 1, 1, 1, 1, 2])
	q.begin_pump()
	assert_int(NetChunker.stream_of(q.next_chunk())).is_equal(2)
	# A snapshot queued mid-clip jumps the remaining voice chunks.
	q.push(NetChunker.STREAM_SNAPSHOT, _bytes(3000, 4))
	q.begin_pump()
	assert_int(NetChunker.stream_of(q.next_chunk())).is_equal(1)
	assert_int(NetChunker.stream_of(q.next_chunk())).is_equal(2)
	assert_int(q.peek_size()).is_equal(0)


func test_events_and_snapshots_keep_fifo_order() -> void:
	var q: NetSendQueue = NetSendQueue.new(16384, 1)
	q.push(NetChunker.STREAM_SNAPSHOT, _bytes(10, 1))
	q.push(NetChunker.STREAM_CONTROL, _bytes(10, 2))
	q.begin_pump()
	assert_int(NetChunker.stream_of(q.next_chunk())).is_equal(NetChunker.STREAM_SNAPSHOT)
	assert_int(NetChunker.stream_of(q.next_chunk())).is_equal(NetChunker.STREAM_CONTROL)
	assert_int(q.high_bytes).is_equal(0)
	assert_bool(q.is_empty()).is_true()


func test_bundles_split_back_into_chunks() -> void:
	var q: NetSendQueue = NetSendQueue.new(1000, 1)
	q.push(NetChunker.STREAM_SNAPSHOT, _bytes(2500, 3))
	q.push(NetChunker.STREAM_CONTROL, _bytes(10, 4))
	q.push(NetChunker.STREAM_VOICE, _bytes(3000, 7))
	q.begin_pump()
	var bundle: PackedByteArray = q.take_bundle(48 * 1024)
	# Three snapshot chunks, one control chunk and one voice chunk in one message.
	assert_int(bundle.size()).is_equal(2500 + 10 + 1000 + 5 * NetChunker.HEADER_SIZE)
	assert_bool(q.take_bundle(48 * 1024).is_empty()).is_true()
	var r: NetChunker = NetChunker.new()
	var done: Array[Dictionary] = r.feed_packet(bundle)
	assert_int(done.size()).is_equal(2)
	assert_int(done[0]["stream"]).is_equal(NetChunker.STREAM_SNAPSHOT)
	assert_int((done[0]["data"] as PackedByteArray).size()).is_equal(2500)
	assert_int(done[1]["stream"]).is_equal(NetChunker.STREAM_CONTROL)
	assert_int(r.pending_messages()).is_equal(1)
	assert_int(r.errors).is_equal(0)


func test_bundle_respects_the_size_cap() -> void:
	var q: NetSendQueue = NetSendQueue.new(1000, 1)
	q.push(NetChunker.STREAM_SNAPSHOT, _bytes(5000, 3))
	q.begin_pump()
	var b: PackedByteArray = q.take_bundle(2500)
	assert_int(b.size()).is_equal(2 * (1000 + NetChunker.HEADER_SIZE))
	# A single chunk over the cap still goes alone.
	var big: NetSendQueue = NetSendQueue.new(4000, 1)
	big.push(NetChunker.STREAM_SNAPSHOT, _bytes(4000, 3))
	big.begin_pump()
	assert_int(big.take_bundle(100).size()).is_equal(4000 + NetChunker.HEADER_SIZE)


func test_truncated_bundle_is_an_error() -> void:
	var chunks: Array[PackedByteArray] = NetChunker.split(0, 1, _bytes(100, 1))
	var r: NetChunker = NetChunker.new()
	assert_array(r.feed_packet(chunks[0].slice(0, 50))).is_empty()
	assert_int(r.errors).is_equal(1)
	var bad_length: PackedByteArray = chunks[0].duplicate()
	bad_length.encode_u16(9, 99)
	assert_bool(r.feed(bad_length).is_empty()).is_true()
	assert_int(r.errors).is_equal(2)


func test_shared_chunks_are_queued_as_is() -> void:
	var chunks: Array[PackedByteArray] = NetChunker.split(
		NetChunker.STREAM_SNAPSHOT, 5, _bytes(40000, 2)
	)
	var a: NetSendQueue = NetSendQueue.new()
	var b: NetSendQueue = NetSendQueue.new()
	a.push_chunks(chunks)
	b.push_chunks(chunks)
	assert_int(a.high_bytes).is_equal(40000 + 3 * NetChunker.HEADER_SIZE)
	a.begin_pump()
	b.begin_pump()
	var r: NetChunker = NetChunker.new()
	var msgs: Array[Dictionary] = r.feed_packet(a.take_bundle(1 << 20))
	assert_int((msgs[0]["data"] as PackedByteArray).size()).is_equal(40000)
	assert_bool(a.take_bundle(1 << 20) == PackedByteArray()).is_true()
	assert_int(b.take_bundle(1 << 20).size()).is_equal(40000 + 3 * NetChunker.HEADER_SIZE)
