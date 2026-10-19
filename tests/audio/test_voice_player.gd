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
	return {"seq": clip, "tick": 0, "type": VoiceService.EVENT_VOICE_LINE, "payload": payload}


func _voice(clip: int, samples: int, part: int = 0, last: bool = true) -> Dictionary:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples * 2)
	return {"clip": clip, "rate": RATE, "pcm": pcm, "part": part, "last": last}


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
	# A one-part clip.
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
	var on_computer: AudioStreamPlayer = vp.players[VoiceBuses.COMPUTER]
	var on_voice: AudioStreamPlayer = vp.players[VoiceBuses.VOICE]
	assert_str(on_computer.bus).is_equal(VoiceBuses.COMPUTER)
	assert_str(on_voice.bus).is_equal(VoiceBuses.VOICE)
	vp.handle_event(_event(1, 1))
	vp.handle_voice(_voice(1, 100))
	assert_object(vp.stream_sink.player_for("computer")).is_same(on_computer)
	assert_bool(on_computer.playing).is_true()
	assert_bool(on_voice.playing).is_false()
	_now = 100
	vp.bus.update(_now)
	vp.handle_event(_event(2, 2))
	vp.handle_voice(_voice(2, 100))
	assert_int(vp.bus.playing_clip()).is_equal(2)
	assert_object(vp.stream_sink.player_for("npc")).is_same(on_voice)
	assert_bool(on_voice.playing).is_true()
	assert_str(on_computer.bus).is_equal(VoiceBuses.COMPUTER)
	assert_str(on_voice.bus).is_equal(VoiceBuses.VOICE)


# FT: FT-AUD-011
func test_parts_reach_the_audio_stream_player() -> void:
	var vp: VoicePlayer = _player()
	vp.handle_event(_event(1, 2))
	vp.handle_voice(_voice(1, 22050))
	var p: AudioStreamPlayer = vp.players[VoiceBuses.VOICE]
	assert_bool(p.playing).is_true()
	assert_object(p.stream).is_instanceof(AudioStreamGenerator)
	assert_int(vp.stream_sink.pending_bytes()).is_equal(44100)
	assert_int(vp.stream_sink.played(1)).is_equal(-1)  # nothing in the generator yet
	for i: int in range(5):
		await await_idle_frame()
	var pushed: int = vp.stream_sink.frames_pushed()
	assert_int(pushed).is_greater(0)
	assert_int(vp.stream_sink.pending_bytes()).is_equal(44100 - 2 * pushed)
	# What was heard is at most what reached the generator.
	assert_int(vp.stream_sink.played(1)).is_between(0, pushed)


# FT: FT-AUD-004, FT-AUD-007
func test_lines_on_the_two_buses_never_share_a_player() -> void:
	var vp: VoicePlayer = _player()
	var on_computer: AudioStreamPlayer = vp.players[VoiceBuses.COMPUTER]
	var on_voice: AudioStreamPlayer = vp.players[VoiceBuses.VOICE]
	vp.handle_event(_event(1, 2, {"resume": true}))
	vp.handle_voice(_voice(1, 1000))
	await await_idle_frame()
	# A computer line preempts: only the NPC player fades, and it keeps its bus.
	_now = 100
	vp.handle_event(_event(2, 1))
	vp.handle_voice(_voice(2, 100))
	assert_int(vp.bus.fading_clip()).is_equal(1)
	vp.stream_sink.process(0.04)
	assert_float(on_voice.volume_linear).is_less(1.0)
	assert_float(on_computer.volume_linear).is_equal(1.0)
	assert_str(on_voice.bus).is_equal(VoiceBuses.VOICE)
	_now = 180
	vp.bus.update(_now)
	assert_int(vp.bus.playing_clip()).is_equal(2)
	assert_str(on_computer.bus).is_equal(VoiceBuses.COMPUTER)
	assert_float(on_voice.volume_linear).is_equal(1.0)  # the stop resets it
	assert_float(on_computer.volume_linear).is_equal(1.0)
	assert_object(on_computer.stream).is_instanceof(AudioStreamGenerator)
	assert_bool(on_computer.playing).is_true()


# FT: FT-AUD-011
func test_a_finished_line_tail_plays_out_before_the_next_on_its_bus() -> void:
	var on_voice: AudioStreamPlayer = AudioStreamPlayer.new()
	var on_computer: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(on_voice)
	add_child(on_computer)
	var sink: VoiceStreamSink = VoiceStreamSink.new(
		{VoiceBuses.VOICE: on_voice, VoiceBuses.COMPUTER: on_computer}
	)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(2 * 1000)
	sink.begin(1, "npc", 22050)
	sink.push(1, pcm, 22050, 0)
	sink.finish(1)
	# A computer line meanwhile leaves the NPC player alone.
	sink.begin(2, "computer", 22050)
	sink.push(2, pcm, 22050, 0)
	assert_str(on_voice.bus).is_equal(VoiceBuses.VOICE)
	assert_int(sink.pending_bytes()).is_equal(4000)
	# The next NPC line queues behind line 1's tail instead of dropping it.
	sink.begin(3, "npc", 22050)
	sink.push(3, pcm, 22050, 0)
	assert_int(sink.pending_bytes()).is_equal(6000)
	var gen: AudioStreamGenerator = on_voice.stream
	assert_object(gen).is_not_null()
	# Stopping line 3 drops only what is queued on its bus.
	sink.stop(3)
	assert_int(sink.pending_bytes()).is_equal(2000)
	assert_object(on_voice.stream).is_same(gen)
	on_voice.queue_free()
	on_computer.queue_free()


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


# FT: FT-AUD-010
func test_local_lines_reject_ids_and_languages_that_are_not_safe_paths() -> void:
	var lines: LocalLines = LocalLines.new("en", "res://tests/audio/no_such_dir")
	for good: String in ["npc.hail", "computer.shields_low", "a.b2.c_3"]:
		assert_bool(lines.valid(good)).override_failure_message(good).is_true()
	for bad: String in [
		"",
		"hail",
		"Npc.hail",
		"1npc.hail",
		"npc.",
		"npc..hail",
		"npc.hail\n",
		"npc.ha il",
		"../npc.hail",
		"npc/../../x.y",
		"npc.hail/x",
		"res://npc.hail"
	]:
		assert_bool(lines.valid(bad)).override_failure_message(bad).is_false()
		assert_object(lines.stream(bad)).is_null()
	for lang: String in ["", "fr", "../en", "en/../it", "EN"]:
		(
			assert_bool(LocalLines.new(lang).valid("npc.hail"))
			. override_failure_message(lang)
			. is_false()
		)
	for lang: String in I18n.LANGUAGES:
		assert_bool(LocalLines.new(lang).valid("npc.hail")).is_true()
	# An invalid line id leaves the subtitle only.
	var vp: VoicePlayer = _player(StubSink.new())
	vp.local_lines = lines
	vp.handle_event(_event(1, 2, {"local": true, "line": "../npc.hail"}))
	assert_bool(vp.bus.holds(1)).is_false()
	assert_array(_subs).has_size(1)
