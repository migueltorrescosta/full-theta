extends GdUnitTestSuite
## PiperProcessSynth's process handling, through PiperStreamSynth and a fake Piper
## (fake_piper.py, run with python3): deadlines, a flooded stderr, crashes mid-request
## and while idle, whole requests and the part cap. Skipped without python3.

const FAKE: String = "res://tests/net/voice/fake_piper.py"

var _synth: PiperStreamSynth


func before_test() -> void:
	_synth = null


func after_test() -> void:
	if _synth != null:
		_synth.stop()


func _has_python() -> bool:
	return OS.get_name() != "Windows" and OS.execute("python3", ["-c", "pass"]) == 0


func _start() -> PiperStreamSynth:
	_synth = PiperStreamSynth.new(
		"python3", ProjectSettings.globalize_path(FAKE), "/x.onnx", "fake"
	)
	_synth.niceness = 0
	_synth.request_base_ms = 500
	_synth.request_ms_per_char = 0
	assert_int(_synth.start()).is_equal(OK)
	return _synth


## Parts until `lasts` requests have ended, or ms have passed.
func _collect(lasts: int, ms: int = 5000) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var end: int = Time.get_ticks_msec() + ms
	var n: int = 0
	while n < lasts and Time.get_ticks_msec() < end:
		for p: Dictionary in _synth.take_parts():
			out.append(p)
			if p["last"]:
				n += 1
		await get_tree().process_frame
	return out


func _summary(parts: Array[Dictionary]) -> Array:
	return parts.map(
		func(p: Dictionary) -> Array: return [p["id"], p["part"], p["last"], p["error"] != ""]
	)


# FT: FT-AUD-019, FT-AUD-015
# A Piper that hangs misses its request's deadline: it is killed and restarted, the
# request ends with an error part (subtitles only), nothing stays pending, and the next
# request is spoken.
func test_a_hung_piper_times_out_and_restarts() -> void:
	if not _has_python():
		return
	_start()
	_synth.request(1, "hang.")
	_synth.request(2, "After.")
	var t0: int = Time.get_ticks_msec()
	var parts: Array[Dictionary] = await _collect(2)
	assert_array(_summary(parts)).is_equal(
		[[1, 0, true, true], [2, 0, false, false], [2, 1, true, false]]
	)
	assert_str(parts[0]["error"]).contains("timed out")
	assert_int(Time.get_ticks_msec() - t0).is_less(4000)
	assert_int(_synth.pending()).is_equal(0)


# FT: FT-AUD-019
# A Piper that writes a lot to stderr doesn't block: its stderr is read and dropped.
func test_a_chatty_stderr_does_not_block() -> void:
	if not _has_python():
		return
	_start()
	_synth.request(1, "spam. And more.")
	var parts: Array[Dictionary] = await _collect(1)
	assert_array(_summary(parts)).is_equal(
		[[1, 0, false, false], [1, 1, false, false], [1, 2, true, false]]
	)


# FT: FT-AUD-019
# A crash mid-request ends that request with an error part; a process that exits while
# idle is relaunched before the next request is sent, which is then spoken.
func test_crashes_mid_request_and_while_idle() -> void:
	if not _has_python():
		return
	_start()
	_synth.request(1, "crash.")
	_synth.request(2, "exit_idle.")
	var parts: Array[Dictionary] = await _collect(2)
	assert_array(_summary(parts)).is_equal(
		[[1, 0, true, true], [2, 0, false, false], [2, 1, true, false]]
	)
	assert_str(parts[0]["error"]).contains("ended")
	# Let the idle process exit before the next request.
	var pid: int = _synth._pid
	var end: int = Time.get_ticks_msec() + 3000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < end:
		OS.delay_msec(10)
	assert_bool(OS.is_process_running(pid)).is_false()
	_synth.request(3, "Spoken.")
	parts = await _collect(1)
	assert_array(_summary(parts)).is_equal([[3, 0, false, false], [3, 1, true, false]])


# FT: FT-AUD-018, FT-ARC-019
# A whole request comes back as one part, its sentences joined, trimmed and normalised
# on the worker thread.
func test_a_whole_request_is_one_trimmed_normalised_part() -> void:
	if not _has_python():
		return
	_start()
	_synth.request(1, "One. Two.", {}, true)
	var parts: Array[Dictionary] = await _collect(1)
	assert_array(_summary(parts)).is_equal([[1, 0, true, false]])
	var pcm: PackedByteArray = parts[0]["pcm"]
	assert_int(pcm.size()).is_equal(20 * 2)
	assert_int(pcm.decode_s16(0)).is_equal(roundi(PcmStitch.PEAK * 32767.0))


# FT: FT-AUD-019
# Parts are capped at MAX_PART_BYTES; a wrapper frame announcing more is refused.
func test_parts_are_capped() -> void:
	var synth: PiperStreamSynth = PiperStreamSynth.new("/py", "/w.py", "/m.onnx")
	var big: PackedByteArray = PackedByteArray()
	big.resize(PiperProcessSynth.MAX_PART_BYTES + 100)
	synth._push({"id": 1, "next_part": 0}, true, big, 1000)
	assert_int((synth.take_parts()[0]["pcm"] as PackedByteArray).size()).is_equal(
		PiperProcessSynth.MAX_PART_BYTES
	)
	var head: PackedByteArray = JSON.stringify({"id": 1}).to_utf8_buffer()
	var stream: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	stream.encode_u32(0, head.size())
	stream.append_array(head)
	var n: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	n.encode_u32(0, PiperProcessSynth.MAX_PART_BYTES + 2)
	stream.append_array(n)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = stream
	var read: Callable = func(k: int) -> PackedByteArray:
		return buf.get_partial_data(mini(k, buf.get_available_bytes()))[1]
	assert_dict(PiperStreamSynth.read_frame(read)).is_empty()
