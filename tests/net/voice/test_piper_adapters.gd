extends GdUnitTestSuite
## The Piper adapters' pure parts, without Piper: sentence splitting, the wrapper's frame
## protocol, WAV parsing, the binary's command line, PcmStitch, and a process that won't
## start failing its requests as subtitles only.


func _frame(head: Dictionary, pcm: PackedByteArray) -> PackedByteArray:
	var h: PackedByteArray = JSON.stringify(head).to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	out.resize(4)
	out.encode_u32(0, h.size())
	out.append_array(h)
	var n: PackedByteArray = PackedByteArray()
	n.resize(4)
	n.encode_u32(0, pcm.size())
	out.append_array(n)
	out.append_array(pcm)
	return out


func _reader(data: PackedByteArray) -> Callable:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	return func(n: int) -> PackedByteArray:
		var got: Array = buf.get_partial_data(mini(n, buf.get_available_bytes()))
		return got[1]


func _wav(rate: int, pcm: PackedByteArray, channels: int = 1) -> PackedByteArray:
	var out: PackedByteArray = "RIFF".to_ascii_buffer()
	out.resize(8)
	out.encode_u32(4, 36 + 8 + pcm.size())
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array("LIST".to_ascii_buffer())
	var list: PackedByteArray = PackedByteArray([4, 0, 0, 0, 1, 2, 3, 4])
	out.append_array(list)
	out.append_array("fmt ".to_ascii_buffer())
	var fmt: PackedByteArray = PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, channels)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2 * channels)
	fmt.encode_u16(16, 2 * channels)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var size: PackedByteArray = PackedByteArray()
	size.resize(4)
	size.encode_u32(0, pcm.size())
	out.append_array(size)
	out.append_array(pcm)
	return out


# FT: FT-AUD-003, FT-AUD-019
# Free text streams per sentence: split at . ! ? and … before a space or the end, with
# closing quotes kept, decimals and abbreviations-without-space untouched, and a piece
# with nothing to say joined to the one before.
func test_sentence_splitting() -> void:
	var split: Callable = PiperBinarySynth.split_sentences
	assert_array(Array(split.call("Mayday, mayday, this is Mara. We are taking fire!"))).is_equal(
		["Mayday, mayday, this is Mara.", "We are taking fire!"]
	)
	assert_array(Array(split.call("Range 3.5 km. Hold."))).is_equal(["Range 3.5 km.", "Hold."])
	assert_array(Array(split.call("No end"))).is_equal(["No end"])
	assert_array(Array(split.call("Wait... what?! Go"))).is_equal(["Wait...", "what?!", "Go"])
	assert_array(Array(split.call('He said "stop." Then  left.'))).is_equal(
		['He said "stop."', "Then  left."]
	)
	assert_array(Array(split.call("Ciao! … ?"))).is_equal(["Ciao! … ?"])
	assert_array(Array(split.call("  "))).is_empty()
	assert_array(Array(split.call("Olá. Está aí?\nSim."))).is_equal(["Olá.", "Está aí?", "Sim."])


# FT: FT-AUD-019
# The wrapper's frames (u32 header length, JSON header, u32 PCM length, PCM) parse in
# order; EOF and a truncated frame give {}.
func test_wrapper_frames() -> void:
	var stream: PackedByteArray = _frame({"id": 0, "ready": true, "rate": 22050}, PackedByteArray())
	stream.append_array(_frame({"id": 3, "last": false}, PackedByteArray([1, 2, 3, 4])))
	stream.append_array(_frame({"id": 3, "last": true}, PackedByteArray()))
	var read: Callable = _reader(stream)
	var ready: Dictionary = PiperStreamSynth.read_frame(read)
	assert_bool(ready["head"]["ready"]).is_true()
	assert_int(int(ready["head"]["rate"])).is_equal(22050)
	var part: Dictionary = PiperStreamSynth.read_frame(read)
	assert_bool(part["pcm"] == PackedByteArray([1, 2, 3, 4])).is_true()
	assert_bool(PiperStreamSynth.read_frame(read)["head"]["last"]).is_true()
	assert_dict(PiperStreamSynth.read_frame(read)).is_empty()
	var cut: PackedByteArray = _frame({"id": 1}, PackedByteArray([9, 9, 9, 9]))
	assert_dict(PiperStreamSynth.read_frame(_reader(cut.slice(0, cut.size() - 1)))).is_empty()
	var line: Dictionary = JSON.parse_string(
		PiperStreamSynth.request_line(5, "Hi.", {"length_scale": 1.05, "speaker": 2})
	)
	assert_dict(line).is_equal({"id": 5.0, "text": "Hi.", "length_scale": 1.05})


# FT: FT-AUD-019
# The binary's WAVs: 16-bit mono PCM found past other chunks; anything else is refused.
func test_wav_parsing() -> void:
	var pcm: PackedByteArray = PackedByteArray([1, 0, 2, 0, 3, 0])
	var wav: Dictionary = PiperBinarySynth.parse_wav(_wav(22050, pcm))
	assert_int(wav["rate"]).is_equal(22050)
	assert_bool(wav["pcm"] == pcm).is_true()
	assert_dict(PiperBinarySynth.parse_wav(_wav(22050, pcm, 2))).is_empty()
	assert_dict(PiperBinarySynth.parse_wav(PackedByteArray([1, 2, 3]))).is_empty()
	assert_dict(PiperBinarySynth.parse_wav(PackedByteArray())).is_empty()


# FT: FT-AUD-019
# The binary runs persistent with JSON input; role settings go on its command line.
func test_binary_command_line() -> void:
	var synth: PiperBinarySynth = PiperBinarySynth.new(
		"/opt/piper/piper", "/opt/piper/espeak-ng-data", "/m/v.onnx"
	)
	assert_str(synth.voice).is_equal("v")
	synth._defaults = {"length_scale": 1.05, "noise_w_scale": 0.333}
	var cmd: Array = synth._command()
	assert_str(cmd[0]).is_equal("/opt/piper/piper")
	(
		assert_array(Array(cmd[1]))
		. is_equal(
			[
				"--quiet",
				"--model",
				"/m/v.onnx",
				"--espeak_data",
				"/opt/piper/espeak-ng-data",
				"--json-input",
				"--length_scale",
				"1.05",
				"--noise_w",
				"0.333",
			]
		)
	)
	var stream: PiperStreamSynth = PiperStreamSynth.new("/py", "/w.py", "/m/v.onnx", "v")
	assert_array(Array(stream._command()[1])).is_equal(["/w.py", "/m/v.onnx", "--threads", "1"])


# FT: FT-AUD-019
# A Piper that never starts gives up after a few tries; its requests then end at once
# with an error part (subtitles only) and nothing blocks.
func test_a_piper_that_cannot_start_fails_requests() -> void:
	if OS.get_name() == "Windows" or not FileAccess.file_exists("/bin/true"):
		return
	var synth: PiperBinarySynth = PiperBinarySynth.new("/bin/true", "/none", "/none.onnx", "none")
	synth.niceness = 0
	assert_int(synth.start()).is_equal(OK)
	synth.request(1, "Hello.")
	var end: int = Time.get_ticks_msec() + 5000
	var parts: Array[Dictionary] = []
	while parts.is_empty() and Time.get_ticks_msec() < end:
		parts.append_array(synth.take_parts())
		await get_tree().process_frame
	synth.stop()
	assert_array(parts).has_size(1)
	assert_bool(parts[0]["last"]).is_true()
	assert_str(parts[0]["error"]).is_not_empty()
	assert_bool(synth.is_dead()).is_true()
	assert_bool(synth.is_ready()).is_false()
	assert_int(synth.pending()).is_equal(0)


# FT: FT-AUD-018
# Names are trimmed to 10 ms around the sound and normalised; stitched pieces are
# joined with a 70 ms gap.
func test_pcm_trim_normalise_join() -> void:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(400)
	pcm.fill(0)
	for i: int in range(100, 120):
		pcm.encode_s16(i * 2, 3000)
	var trimmed: PackedByteArray = PcmStitch.trim(pcm, 1000)
	assert_int(trimmed.size() / 2).is_equal(20 + 2 * 10)
	assert_int(PcmStitch.trim(PackedByteArray([0, 0, 1, 0]), 1000).size()).is_equal(0)
	var loud: PackedByteArray = PcmStitch.normalise(trimmed)
	assert_int(loud.decode_s16(20)).is_equal(roundi(PcmStitch.PEAK * 32767.0))
	var parts: Array[PackedByteArray] = [trimmed, PackedByteArray(), trimmed]
	var joined: PackedByteArray = PcmStitch.join(parts, 1000)
	assert_int(joined.size()).is_equal(trimmed.size() * 2 + PcmStitch.GAP_MS * 2)
