extends GdUnitTestSuite
## S4 spike: chunker and send-queue priority (spike evidence for FT-NET-038;
## the id stays pending until T045 promotes the code).


func _bytes(size: int, value: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(size)
	data.fill(value)
	return data


func test_split_sizes_and_headers() -> void:
	var chunks: Array[PackedByteArray] = S4Chunker.split(2, 77, _bytes(40000, 1), 16384)
	assert_int(chunks.size()).is_equal(3)
	assert_int(chunks[0].size()).is_equal(S4Chunker.HEADER_SIZE + 16384)
	assert_int(chunks[2].size()).is_equal(S4Chunker.HEADER_SIZE + 40000 - 2 * 16384)
	assert_int(S4Chunker.stream_of(chunks[1])).is_equal(2)
	assert_int(S4Chunker.msg_id_of(chunks[1])).is_equal(77)
	assert_int(S4Chunker.index_of(chunks[1])).is_equal(1)
	assert_int(S4Chunker.count_of(chunks[1])).is_equal(3)


func test_empty_message_is_one_chunk() -> void:
	var chunks: Array[PackedByteArray] = S4Chunker.split(0, 1, PackedByteArray(), 16384)
	assert_int(chunks.size()).is_equal(1)
	var msg: Dictionary = S4Chunker.new().feed(chunks[0])
	assert_int((msg["data"] as PackedByteArray).size()).is_equal(0)


func test_interleaved_streams_reassemble() -> void:
	var voice: PackedByteArray = _bytes(132440, 7)
	var snap: PackedByteArray = var_to_bytes({"seq": 5, "pad": _bytes(70000, 3)})
	var v: Array[PackedByteArray] = S4Chunker.split(S4Chunker.STREAM_VOICE, 1, voice, 16384)
	var s: Array[PackedByteArray] = S4Chunker.split(S4Chunker.STREAM_SNAPSHOT, 2, snap, 16384)
	var r: S4Chunker = S4Chunker.new()
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
	assert_int(done[0]["stream"]).is_equal(S4Chunker.STREAM_SNAPSHOT)
	assert_bool(done[0]["data"] == snap).is_true()
	assert_bool(done[1]["data"] == voice).is_true()
	assert_int(r.errors).is_equal(0)
	assert_int(r.pending_messages()).is_equal(0)


func test_out_of_order_chunk_is_an_error() -> void:
	var c: Array[PackedByteArray] = S4Chunker.split(1, 9, _bytes(40000, 1), 16384)
	var r: S4Chunker = S4Chunker.new()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_bool(r.feed(c[2]).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)


func _chunk(stream: int, msg_id: int, index: int, count: int, size: int) -> PackedByteArray:
	var chunk: PackedByteArray = PackedByteArray()
	chunk.resize(S4Chunker.HEADER_SIZE)
	chunk.encode_u8(0, stream)
	chunk.encode_u32(1, msg_id)
	chunk.encode_u16(5, index)
	chunk.encode_u16(7, count)
	chunk.append_array(_bytes(size, 5))
	return chunk


func test_duplicate_chunk_drops_the_message() -> void:
	var c: Array[PackedByteArray] = S4Chunker.split(1, 9, _bytes(40000, 1), 16384)
	var r: S4Chunker = S4Chunker.new()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_bool(r.feed(c[0]).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)
	assert_int(r.pending_messages()).is_equal(0)
	# The rest of the message can't complete it any more.
	assert_bool(r.feed(c[1]).is_empty()).is_true()
	assert_bool(r.feed(c[2]).is_empty()).is_true()
	assert_int(r.pending_messages()).is_equal(0)
	# A later message on the stream still arrives.
	var next: Array[PackedByteArray] = S4Chunker.split(1, 10, _bytes(100, 2), 16384)
	assert_bool(r.feed(next[0]).is_empty()).is_false()


func test_malformed_chunks_are_rejected() -> void:
	var r: S4Chunker = S4Chunker.new()
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
	var r: S4Chunker = S4Chunker.new()
	for id: int in range(1, 100):
		assert_bool(r.feed(_chunk(1, id, 0, 2, 10)).is_empty()).is_true()
	assert_int(r.pending_messages()).is_equal(1)
	assert_int(r.errors).is_equal(98)
	var msg: Dictionary = r.feed(_chunk(1, 99, 1, 2, 10))
	assert_int(msg["msg_id"]).is_equal(99)
	assert_int((msg["data"] as PackedByteArray).size()).is_equal(20)
	assert_int(r.pending_messages()).is_equal(0)


func test_message_over_the_size_cap_is_rejected() -> void:
	var r: S4Chunker = S4Chunker.new()
	var size: int = 60000
	var count: int = S4Chunker.MAX_MESSAGE_SIZE / size + 1
	for i: int in range(count - 1):
		assert_bool(r.feed(_chunk(2, 7, i, count, size)).is_empty()).is_true()
	assert_int(r.errors).is_equal(0)
	assert_int(r.pending_messages()).is_equal(1)
	assert_bool(r.feed(_chunk(2, 7, count - 1, count, size)).is_empty()).is_true()
	assert_int(r.errors).is_equal(1)
	assert_int(r.pending_messages()).is_equal(0)


func test_snapshot_chunks_go_before_earlier_voice() -> void:
	var q: S4SendQueue = S4SendQueue.new(16384, 1)
	q.push(S4Chunker.STREAM_VOICE, _bytes(132440, 7))
	q.push(S4Chunker.STREAM_SNAPSHOT, _bytes(70000, 3))
	q.begin_pump()
	var order: Array[int] = []
	while q.peek_size() > 0:
		order.append(S4Chunker.stream_of(q.next_chunk()))
	# Five snapshot chunks, then only one voice chunk this pump.
	assert_array(order).is_equal([1, 1, 1, 1, 1, 2])
	q.begin_pump()
	assert_int(S4Chunker.stream_of(q.next_chunk())).is_equal(2)
	# A snapshot queued mid-clip jumps the remaining voice chunks.
	q.push(S4Chunker.STREAM_SNAPSHOT, _bytes(3000, 4))
	q.begin_pump()
	assert_int(S4Chunker.stream_of(q.next_chunk())).is_equal(1)
	assert_int(S4Chunker.stream_of(q.next_chunk())).is_equal(2)
	assert_int(q.peek_size()).is_equal(0)


func test_events_and_snapshots_keep_fifo_order() -> void:
	var q: S4SendQueue = S4SendQueue.new(16384, 1)
	q.push(S4Chunker.STREAM_SNAPSHOT, _bytes(10, 1))
	q.push(S4Chunker.STREAM_CONTROL, _bytes(10, 2))
	q.begin_pump()
	assert_int(S4Chunker.stream_of(q.next_chunk())).is_equal(S4Chunker.STREAM_SNAPSHOT)
	assert_int(S4Chunker.stream_of(q.next_chunk())).is_equal(S4Chunker.STREAM_CONTROL)
	assert_int(q.high_bytes).is_equal(0)
	assert_bool(q.is_empty()).is_true()
