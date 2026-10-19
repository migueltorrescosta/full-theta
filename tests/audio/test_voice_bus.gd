extends GdUnitTestSuite
## VoiceBus queue logic with a recording stub sink and a fake clock, no audio output
## (FT-AUD-011). Clips run at 1,000 Hz, so one sample is one millisecond.

const RATE: int = 1000
const StubSink = preload("res://tests/audio/voice_sink_stub.gd")

var _bus: VoiceBus
var _sink: StubSink


func before_test() -> void:
	_bus = VoiceBus.new()
	_sink = StubSink.new()
	_bus.sink = _sink


func _payload(clip: int, priority: int, extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {
		"clip": clip,
		"line": "test.l%d" % clip,
		"text": "Line %d" % clip,
		"role": "computer" if priority <= 1 else "npc",
		"priority": priority,
		"max_age_ms": 60_000,
		"coalesce": "",
		"resume": false,
		"audio": true,
	}
	p.merge(extra, true)
	return p


func _pcm(samples: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(samples * 2)
	return b


## Offers a line with one whole part of `samples` at `now`.
func _line(clip: int, priority: int, samples: int, now: int, extra: Dictionary = {}) -> void:
	assert_bool(_bus.offer(_payload(clip, priority, extra), now)).is_true()
	_bus.add_part(clip, 0, RATE, _pcm(samples), true, now)


# FT: FT-AUD-007, FT-AUD-011
func test_preemption_fades_80_ms_then_resumes_from_fade_start() -> void:
	assert_int(VoiceBus.FADE_MS).is_equal(80)
	_line(1, 2, 1000, 0, {"resume": true})
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.update(300)
	_line(2, 1, 500, 300)
	assert_array(_sink.named("fade")).is_equal([["fade", 1, 80]])
	assert_int(_bus.playing_clip()).is_equal(-1)
	assert_int(_bus.fading_clip()).is_equal(1)
	_bus.update(379)
	assert_array(_sink.named("begin")).has_size(1)
	_bus.update(380)
	assert_array(_sink.named("stop")).is_equal([["stop", 1]])
	assert_int(_bus.playing_clip()).is_equal(2)
	_bus.update(879)
	assert_int(_bus.playing_clip()).is_equal(2)
	_bus.update(880)
	# The preempted line resumes from where its fade began: sample 300 of 1000.
	assert_int(_bus.playing_clip()).is_equal(1)
	assert_array(_sink.calls.slice(-2)).is_equal(
		[["begin", 1, "npc", RATE], ["push", 1, 1000, 300]]
	)
	_bus.update(1580)
	assert_array(_bus.finished).is_equal([2, 1])
	assert_array(_bus.dropped).is_empty()


# FT: FT-AUD-007, FT-AUD-011
func test_preempted_line_without_resume_is_dropped() -> void:
	_line(1, 3, 1000, 0)
	_bus.update(200)
	_line(2, 2, 100, 200)
	assert_str(_bus.drop_reason(1)).is_equal(VoiceBus.PREEMPTED)
	assert_bool(_bus.holds(1)).is_true()  # still fading out
	_bus.update(280)
	assert_bool(_bus.holds(1)).is_false()
	assert_int(_bus.playing_clip()).is_equal(2)
	_bus.update(380)
	assert_array(_bus.finished).is_equal([2])
	assert_int(_bus.playing_clip()).is_equal(-1)
	assert_array(_bus.queued_clips()).is_empty()


# FT: FT-AUD-007, FT-AUD-011
func test_each_higher_priority_preempts_p3_to_p0() -> void:
	_line(3, 3, 1000, 0, {"resume": true})
	_line(2, 2, 1000, 10, {"resume": true})
	_bus.update(90)
	assert_int(_bus.playing_clip()).is_equal(2)
	_line(1, 1, 1000, 100, {"resume": true})
	_bus.update(180)
	assert_int(_bus.playing_clip()).is_equal(1)
	_line(0, 0, 100, 200)
	_bus.update(280)
	assert_int(_bus.playing_clip()).is_equal(0)
	var faded: Array = _sink.named("fade").map(func(c: Array) -> int: return c[1])
	assert_array(faded).is_equal([3, 2, 1])
	# Then back down in priority order, each resuming.
	_bus.update(380)
	assert_int(_bus.playing_clip()).is_equal(1)
	assert_array(_bus.queued_clips()).is_equal([3, 2])


# FT: FT-AUD-007, FT-AUD-011
func test_lower_priority_does_not_preempt_and_queue_plays_p0_first() -> void:
	_line(9, 0, 100, 0)
	_line(3, 3, 100, 1)
	_line(1, 1, 100, 2)
	_line(2, 2, 100, 3)
	_line(0, 0, 100, 4)
	assert_array(_sink.named("fade")).is_empty()
	for t: int in [100, 200, 300, 400, 500]:
		_bus.update(t)
	assert_array(_bus.finished).is_equal([9, 0, 1, 2, 3])


# FT: FT-AUD-007, FT-AUD-011
func test_ready_lower_priority_plays_while_higher_waits_for_audio() -> void:
	_bus.offer(_payload(1, 1), 0)
	_line(2, 2, 1000, 0, {"resume": true})
	assert_int(_bus.playing_clip()).is_equal(2)
	_bus.add_part(1, 0, RATE, _pcm(100), true, 50)
	assert_int(_bus.fading_clip()).is_equal(2)
	_bus.update(130)
	assert_int(_bus.playing_clip()).is_equal(1)


# FT: FT-AUD-008, FT-AUD-011
func test_equal_priorities_queue_fifo() -> void:
	_line(1, 2, 100, 0)
	_line(2, 2, 100, 1)
	_line(3, 2, 100, 2)
	assert_array(_bus.queued_clips()).is_equal([2, 3])
	for t: int in [100, 200, 300]:
		_bus.update(t)
	assert_array(_bus.finished).is_equal([1, 2, 3])
	assert_array(_sink.named("fade")).is_empty()
	assert_array(_bus.dropped).is_empty()


# FT: FT-AUD-008, FT-AUD-011
func test_queued_head_blocks_later_lines_of_its_priority() -> void:
	_bus.offer(_payload(1, 2), 0)
	_line(2, 2, 100, 0)
	assert_int(_bus.playing_clip()).is_equal(-1)
	_bus.add_part(1, 0, RATE, _pcm(100), true, 10)
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.update(110)
	assert_int(_bus.playing_clip()).is_equal(2)


# FT: FT-AUD-008, FT-AUD-011
func test_newer_line_with_same_coalescing_key_drops_queued_one() -> void:
	_line(1, 2, 1000, 0, {"coalesce": "contact:v3"})
	_line(2, 2, 100, 10, {"coalesce": "contact:v3"})
	_line(3, 2, 100, 20, {"coalesce": "contact:v3"})
	_line(4, 2, 100, 30, {"coalesce": "hail"})
	_line(5, 2, 100, 40)
	_line(6, 2, 100, 50)  # an empty key never coalesces
	# The playing line keeps playing; only the queued one is superseded.
	assert_int(_bus.playing_clip()).is_equal(1)
	assert_array(_bus.queued_clips()).is_equal([3, 4, 5, 6])
	assert_str(_bus.drop_reason(2)).is_equal(VoiceBus.COALESCED)
	assert_bool(_bus.holds(2)).is_false()
	for t: int in [1000, 1100, 1200, 1300, 1400]:
		_bus.update(t)
	assert_array(_bus.finished).is_equal([1, 3, 4, 5, 6])


# FT: FT-AUD-008, FT-AUD-011
func test_queued_line_older_than_max_age_is_dropped() -> void:
	_line(1, 2, 1000, 0, {"max_age_ms": 100})
	_line(2, 2, 100, 0, {"max_age_ms": 500})
	_bus.update(500)
	assert_array(_bus.queued_clips()).is_equal([2])
	_bus.update(501)
	assert_array(_bus.queued_clips()).is_empty()
	assert_str(_bus.drop_reason(2)).is_equal(VoiceBus.EXPIRED)
	# The playing line is past its own max age but isn't queued, so it plays on.
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.update(1000)
	assert_array(_bus.finished).is_equal([1])


# FT: FT-AUD-008, FT-AUD-011
func test_line_whose_audio_never_arrives_expires() -> void:
	_bus.offer(_payload(1, 1, {"max_age_ms": 200}), 0)
	_bus.update(200)
	assert_array(_bus.queued_clips()).is_equal([1])
	assert_array(_sink.calls).is_empty()
	_bus.update(201)
	assert_str(_bus.drop_reason(1)).is_equal(VoiceBus.EXPIRED)
	assert_bool(_bus.holds(1)).is_false()
	# Late audio for it is held only briefly, never played.
	_bus.add_part(1, 0, RATE, _pcm(100), true, 300)
	_bus.update(300 + VoiceBus.ORPHAN_MS + 1)
	assert_bool(_bus.holds(1)).is_false()
	assert_array(_sink.calls).is_empty()


# FT: FT-AUD-008, FT-AUD-011
func test_resumable_line_waiting_to_resume_can_expire() -> void:
	_line(1, 2, 1000, 0, {"resume": true, "max_age_ms": 400})
	_bus.update(100)
	_line(2, 0, 500, 100)
	_bus.update(180)
	_bus.update(401)
	assert_str(_bus.drop_reason(1)).is_equal(VoiceBus.EXPIRED)
	_bus.update(680)
	assert_array(_bus.finished).is_equal([2])
	assert_int(_bus.playing_clip()).is_equal(-1)


# FT: FT-AUD-011
func test_audio_false_line_never_enters_the_bus() -> void:
	_line(1, 2, 1000, 0)
	_line(2, 2, 100, 0, {"coalesce": "k"})
	assert_bool(_bus.offer(_payload(3, 0, {"audio": false}), 10)).is_false()
	assert_bool(_bus.holds(3)).is_false()
	assert_array(_sink.named("fade")).is_empty()
	# It still supersedes a queued line with its coalescing key.
	assert_bool(_bus.offer(_payload(4, 2, {"audio": false, "coalesce": "k"}), 20)).is_false()
	assert_str(_bus.drop_reason(2)).is_equal(VoiceBus.COALESCED)
	assert_array(_bus.queued_clips()).is_empty()


# FT: FT-AUD-011
func test_line_starts_only_once_its_first_part_arrives() -> void:
	_bus.offer(_payload(1, 2), 0)
	_bus.add_part(1, 1, RATE, _pcm(200), true, 10)
	assert_array(_sink.calls).is_empty()
	_bus.add_part(1, 0, RATE, _pcm(100), false, 20)
	# Both parts go out back to back, so they play gaplessly.
	assert_array(_sink.calls).is_equal(
		[["begin", 1, "npc", RATE], ["push", 1, 100, 0], ["push", 1, 200, 0]]
	)
	_bus.update(319)
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.update(320)
	assert_array(_bus.finished).is_equal([1])
	assert_int(_bus.underruns).is_equal(0)


# FT: FT-AUD-011
func test_missing_next_part_waits_and_counts_an_underrun() -> void:
	_bus.offer(_payload(1, 2), 0)
	_bus.add_part(1, 0, RATE, _pcm(100), false, 0)
	_bus.update(100)
	assert_int(_bus.underruns).is_equal(1)
	assert_int(_bus.playing_clip()).is_equal(1)
	_line(2, 2, 100, 120)
	assert_int(_bus.playing_clip()).is_equal(1)  # the waiting line still holds the bus
	_bus.add_part(1, 1, RATE, _pcm(100), true, 150)
	_bus.update(249)
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.update(250)
	assert_array(_bus.finished).is_equal([1])
	assert_int(_bus.playing_clip()).is_equal(2)
	assert_int(_bus.underruns).is_equal(1)


# FT: FT-AUD-011
func test_line_starved_too_long_is_dropped() -> void:
	_bus.offer(_payload(1, 2), 0)
	_bus.add_part(1, 0, RATE, _pcm(100), false, 0)
	_bus.update(100)
	_bus.update(100 + VoiceBus.STALL_MS + 1)
	assert_str(_bus.drop_reason(1)).is_equal(VoiceBus.STALLED)
	assert_array(_sink.named("stop")).is_equal([["stop", 1]])
	assert_bool(_bus.holds(1)).is_false()


# FT: FT-AUD-007, FT-AUD-011
func test_resume_position_spans_parts() -> void:
	_bus.offer(_payload(1, 2, {"resume": true}), 0)
	_bus.add_part(1, 0, RATE, _pcm(200), false, 0)
	_bus.add_part(1, 1, RATE, _pcm(200), true, 0)
	_bus.update(250)
	_line(2, 1, 100, 250)
	assert_int(_bus.held_parts(1)).is_equal(1)  # part 0 is behind the resume point
	_bus.update(330)
	_bus.update(430)
	assert_array(_sink.calls.slice(-2)).is_equal([["begin", 1, "npc", RATE], ["push", 1, 200, 50]])
	_bus.update(580)
	assert_array(_bus.finished).is_equal([2, 1])
	# The same, when the sink reports hearing less than the clock (audio buffered or in
	# the output latency): the line resumes from what was heard.
	before_test()
	_bus.offer(_payload(1, 2, {"resume": true}), 0)
	_bus.add_part(1, 0, RATE, _pcm(200), false, 0)
	_bus.add_part(1, 1, RATE, _pcm(200), true, 0)
	_sink.heard = 180  # 70 ms still buffered or in the output latency
	_bus.update(250)
	assert_int(_bus.held_parts(1)).is_equal(2)  # part 0 is still heard, so kept
	_line(2, 1, 100, 250)
	assert_int(_bus.held_parts(1)).is_equal(2)  # part 0 is not behind the resume point
	_sink.heard = -1
	_bus.update(330)
	_bus.update(430)
	assert_array(_sink.calls.slice(-3)).is_equal(
		[["begin", 1, "npc", RATE], ["push", 1, 200, 180], ["push", 1, 200, 0]]
	)
	# A sink reporting more than the clock never moves the resume point ahead.
	_bus.update(450)
	_sink.heard = 10_000
	_line(3, 0, 100, 450)
	_bus.update(530)
	_bus.update(630)
	assert_array(_sink.calls.slice(-2)).is_equal([["begin", 1, "npc", RATE], ["push", 1, 200, 0]])


# FT: FT-AUD-011
func test_parts_leave_the_bus_once_played_and_after_last() -> void:
	_bus.offer(_payload(1, 2), 0)
	for part: int in range(3):
		_bus.add_part(1, part, RATE, _pcm(100), part == 2, 0)
	assert_int(_bus.held_parts(1)).is_equal(3)
	_bus.update(150)
	assert_int(_bus.held_parts(1)).is_equal(2)
	_bus.update(300)
	assert_array(_bus.finished).is_equal([1])
	assert_bool(_bus.holds(1)).is_false()
	assert_array(_sink.named("finish")).is_equal([["finish", 1]])
	# A stray part after the end is not played.
	_bus.add_part(1, 3, RATE, _pcm(100), true, 310)
	assert_int(_bus.playing_clip()).is_equal(-1)
	_bus.update(310 + VoiceBus.ORPHAN_MS + 1)
	assert_bool(_bus.holds(1)).is_false()


# FT: FT-AUD-011
func test_parts_before_their_event_are_kept_briefly() -> void:
	_bus.add_part(1, 0, RATE, _pcm(100), true, 0)
	assert_int(_bus.held_parts(1)).is_equal(1)
	_bus.offer(_payload(1, 2), 10)
	assert_int(_bus.playing_clip()).is_equal(1)
	_bus.add_part(2, 0, RATE, _pcm(100), true, 0)
	_bus.update(VoiceBus.ORPHAN_MS + 1)
	assert_bool(_bus.holds(2)).is_false()


# FT: FT-AUD-011
func test_empty_last_part_ends_the_clip() -> void:
	_bus.offer(_payload(1, 2), 0)
	_bus.add_part(1, 0, RATE, _pcm(100), false, 0)
	_bus.add_part(1, 1, RATE, PackedByteArray(), true, 10)
	_bus.update(100)
	assert_array(_bus.finished).is_equal([1])
	assert_int(_bus.underruns).is_equal(0)
