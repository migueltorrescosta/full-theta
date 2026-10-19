extends GdUnitTestSuite
## VoicePlayer in a headless scene (dummy audio driver): voice_line events and VOICE
## messages reach the bus, the sink and the AudioStreamPlayer, and subtitles fire for
## every line whatever happens to its audio.

const RATE: int = 1000
const StubSink = preload("res://tests/audio/voice_sink_stub.gd")

var _now: int = 0
var _subs: Array[Dictionary] = []
var _players: Array[VoicePlayer] = []


## A 0.4 s stream standing in for an Ogg Vorbis file.
class StubStream:
	extends AudioStream

	func _get_length() -> float:
		return 0.4


## LocalLines with one prerendered line.
class StubLocalLines:
	extends LocalLines

	func _init() -> void:
		super("en")

	func stream(line_id: String) -> AudioStream:
		return StubStream.new() if line_id == "computer.shields_low" else null


func before_test() -> void:
	_now = 0
	_subs.clear()


func _player(stub: VoiceSink = null) -> VoicePlayer:
	var vp: VoicePlayer = VoicePlayer.new()
	if stub != null:
		vp.bus.sink = stub
	vp.clock = func() -> int: return _now
	vp.local_lines = StubLocalLines.new()
	vp.subtitle.connect(func(e: Dictionary) -> void: _subs.append(e))
	add_child(vp)
	_players.append(vp)
	return vp


func _event(clip: int, priority: int, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {
		"clip": clip,
		"line": "npc.l%d" % clip,
		"text": "Line %d." % clip,
		"role": "computer" if priority <= 1 else "npc",
		"priority": priority,
		"max_age_ms": 1000,
		"coalesce": "",
		"resume": false,
		"audio": true,
	}
	payload.merge(extra, true)
	return {"seq": clip, "tick": 0, "type": VoicePlayer.EVENT_TYPE, "payload": payload}


func _voice(clip: int, samples: int, part: int = -1, last: bool = true) -> Dictionary:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples * 2)
	var msg: Dictionary = {"clip": clip, "rate": RATE, "pcm": pcm}
	if part >= 0:
		msg["part"] = part
		msg["last"] = last
	return msg


func after_test() -> void:
	for vp: VoicePlayer in _players:
		vp.queue_free()
	_players.clear()


# FT: FT-AUD-010, FT-AUD-011
func test_events_and_voice_reach_the_sink_and_subtitles_fire() -> void:
	var sink: StubSink = StubSink.new()
	var vp: VoicePlayer = _player(sink)
	assert_bool(vp.handle_event({"type": "hit", "payload": {}})).is_false()
	assert_bool(vp.handle_event(_event(1, 2))).is_true()
	assert_array(_subs).has_size(1)
	var client: NetClient = NetClient.new()
	client.voice_clips.append(_voice(1, 100, 0, false))
	client.voice_clips.append(_voice(1, 100, 1, true))
	vp.pump(client)
	assert_array(client.voice_clips).is_empty()
	assert_int(vp.bus.playing_clip()).is_equal(1)
	assert_array(sink.calls.slice(0, 3)).is_equal(
		[["begin", 1, "npc", RATE], ["push", 1, 100, 0], ["push", 1, 100, 0]]
	)
	# A VOICE message without part/last is part 0 and the last.
	vp.handle_event(_event(2, 2))
	vp.handle_voice(_voice(2, 50))
	_now = 200
	await await_idle_frame()
	assert_int(vp.bus.playing_clip()).is_equal(2)
	_now = 250
	await await_idle_frame()
	assert_array(vp.bus.finished).is_equal([1, 2])


# FT: FT-AUD-010
func test_every_line_is_subtitled_whatever_happens_to_its_audio() -> void:
	var vp: VoicePlayer = _player(StubSink.new())
	vp.handle_event(_event(1, 3))  # preempted, no resume
	vp.handle_voice(_voice(1, 1000))
	vp.handle_event(_event(2, 2, {"coalesce": "k"}))  # coalesced
	vp.handle_event(_event(3, 2, {"coalesce": "k", "max_age_ms": 10}))  # expires
	vp.handle_event(_event(4, 1, {"audio": false}))  # subtitles only (D110)
	vp.handle_event(_event(5, 1, {"local": true, "line": "computer.missing"}))  # no clip
	vp.handle_event(_event(6, 0))  # preempts 1
	vp.handle_voice(_voice(6, 100))
	_now = 100
	vp.bus.update(_now)
	assert_str(vp.bus.drop_reason(1)).is_equal(VoiceBus.PREEMPTED)
	assert_str(vp.bus.drop_reason(2)).is_equal(VoiceBus.COALESCED)
	assert_str(vp.bus.drop_reason(3)).is_equal(VoiceBus.EXPIRED)
	assert_bool(vp.bus.holds(4)).is_false()
	assert_bool(vp.bus.holds(5)).is_false()
	var clips: Array = _subs.map(func(e: Dictionary) -> int: return e["clip"])
	assert_array(clips).is_equal([1, 2, 3, 4, 5, 6])
	assert_array(vp.subtitles.active(_now)).has_size(6)


# FT: FT-AUD-011
func test_local_line_plays_from_the_library_without_voice_messages() -> void:
	var sink: StubSink = StubSink.new()
	var vp: VoicePlayer = _player(sink)
	vp.handle_event(_event(1, 1, {"local": true, "line": "computer.shields_low", "resume": true}))
	assert_int(vp.bus.playing_clip()).is_equal(1)
	assert_array(sink.calls).is_equal([["begin", 1, "computer", RATE], ["stream", 1, 0]])
	# It preempts and resumes by position, like a streamed line.
	_now = 100
	vp.handle_event(_event(2, 0))
	vp.handle_voice(_voice(2, 100))
	_now = 180
	vp.bus.update(_now)
	_now = 280
	vp.bus.update(_now)
	assert_array(sink.calls.slice(-2)).is_equal(
		[["begin", 1, "computer", RATE], ["stream", 1, 100]]
	)
	_now = 580
	vp.bus.update(_now)
	assert_array(vp.bus.finished).is_equal([2, 1])


# FT: FT-AUD-004
func test_computer_lines_play_on_the_filtered_bus_and_npc_lines_do_not() -> void:
	var vp: VoicePlayer = _player()
	assert_object(vp.stream_sink).is_not_null()
	var computer: int = AudioServer.get_bus_index(VoiceBuses.COMPUTER)
	var voice: int = AudioServer.get_bus_index(VoiceBuses.VOICE)
	assert_int(voice).is_greater_equal(0)
	assert_int(computer).is_greater_equal(0)
	assert_str(AudioServer.get_bus_send(computer)).is_equal(VoiceBuses.VOICE)
	assert_str(AudioServer.get_bus_send(voice)).is_equal("Master")
	var kinds: Array[String] = []
	for i: int in range(AudioServer.get_bus_effect_count(computer)):
		kinds.append(AudioServer.get_bus_effect(computer, i).get_class())
	assert_array(kinds).is_equal(
		[
			"AudioEffectDelay",
			"AudioEffectHighPassFilter",
			"AudioEffectLowPassFilter",
			"AudioEffectDistortion"
		]
	)
	var crush: AudioEffectDistortion = AudioServer.get_bus_effect(computer, 3)
	assert_int(crush.mode).is_equal(AudioEffectDistortion.MODE_LOFI)
	assert_int(AudioServer.get_bus_effect_count(voice)).is_equal(0)
	vp.handle_event(_event(1, 1))
	vp.handle_voice(_voice(1, 100))
	assert_str(vp.player.bus).is_equal(VoiceBuses.COMPUTER)
	_now = 100
	vp.bus.update(_now)
	vp.handle_event(_event(2, 2))
	vp.handle_voice(_voice(2, 100))
	assert_int(vp.bus.playing_clip()).is_equal(2)
	assert_str(vp.player.bus).is_equal(VoiceBuses.VOICE)


# FT: FT-AUD-011
func test_parts_reach_the_audio_stream_player() -> void:
	var vp: VoicePlayer = _player()
	vp.handle_event(_event(1, 2))
	vp.handle_voice(_voice(1, 22050))
	assert_bool(vp.player.playing).is_true()
	assert_object(vp.player.stream).is_instanceof(AudioStreamGenerator)
	assert_int(vp.stream_sink.pending_bytes()).is_equal(44100)
	for i: int in range(5):
		await await_idle_frame()
	assert_int(vp.stream_sink.frames_pushed).is_greater(0)
	assert_int(vp.stream_sink.pending_bytes()).is_equal(44100 - 2 * vp.stream_sink.frames_pushed)


# FT: FT-AUD-010
func test_local_line_without_a_file_is_subtitled_only() -> void:
	var lines: LocalLines = LocalLines.new("en", "res://tests/audio/no_such_dir")
	assert_str(lines.path("npc.hail")).is_equal("res://tests/audio/no_such_dir/en/npc.hail.ogg")
	assert_object(lines.stream("npc.hail")).is_null()
	var vp: VoicePlayer = _player(StubSink.new())
	vp.local_lines = lines
	vp.handle_event(_event(1, 2, {"local": true, "line": "npc.hail"}))
	assert_bool(vp.bus.holds(1)).is_false()
	assert_array(_subs).has_size(1)
