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
