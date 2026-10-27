extends GdUnitTestSuite
## VoiceService without a network or Piper: a capturing transport, the spy synth and a
## prerender directory written by VoiceFixture.

const DIR: String = "user://test_voice_service"
const CLOSED: Dictionary = {
	"ship_names": ["Valiant"],
	"callsigns": ["Viper Three", "Ghost One"],
	"npc_names": ["Mara Quill"],
}
const CONTACT: Dictionary = {"callsign": "Viper Three", "bearing": 342, "range": 18}


## Records what the service posts instead of queueing it for a net thread.
class CaptureTransport:
	extends NetTransport
	## [sessions, tick, type, payload]
	var events: Array = []
	## [session, decoded VOICE fields]
	var voice: Array = []
	## "event" or "voice", in posting order.
	var order: PackedStringArray = []

	func post_event(
		sessions: PackedInt32Array, tick: int, type: String, payload: Dictionary
	) -> void:
		events.append([sessions, tick, type, payload])
		order.append("event")

	func post_voice(session: int, data: PackedByteArray) -> void:
		voice.append([session, NetProtocol.decode(data)])
		order.append("voice")


var _fx: VoiceFixture
var _net: CaptureTransport
var _svc: VoiceService


func before_test() -> void:
	_fx = VoiceFixture.new(DIR)
	for lang: String in ["en", "pt_PT", "it"]:
		_fx.write(lang)
	_net = CaptureTransport.new()
	_svc = VoiceService.new(_net, _fx.factory())
	_svc.clip_dir = DIR
	_svc.allow_dev_voices = true


func after_test() -> void:
	_svc.stop()
	_svc.free()
	_fx.clean()


## Starts lang with the closed set and lets the spies answer it.
func _start(lang: String = "en") -> void:
	_svc.start_session(lang, CLOSED)
	_svc._process(0.0)
	assert_bool(_svc.closed_set_done()).is_true()


## Starts en with spies that hold their parts, and lets the closed set through.
func _start_held() -> void:
	_svc.start_session("en", CLOSED)
	assert_bool(_svc.closed_set_done()).is_false()
	for spy: SpyVoiceSynth in _fx.spies.values():
		spy.release()
	_svc._process(0.0)
	assert_bool(_svc.closed_set_done()).is_true()


func _texts(log: Array[Dictionary], voice: String) -> Array:
	return (
		log
		. filter(func(r: Dictionary) -> bool: return r["voice"] == voice)
		. map(func(r: Dictionary) -> String: return r["text"])
	)


# FT: FT-AUD-018, FT-ARC-019, FT-AUD-019
# At Start the service starts one synth per distinct runtime voice and synthesises every
# closed-set item exactly once per role, with the role's settings; then it reports the
# closed set ready and records the Start time for the language.
func test_start_synthesises_the_closed_set_once_per_role() -> void:
	var ready: Array = []
	_svc.closed_set_ready.connect(func(lang: String, ms: int) -> void: ready.append([lang, ms]))
	_svc.start_session("en", CLOSED)
	var items: Array = ["Valiant", "Viper Three", "Ghost One", "Mara Quill"]
	assert_int(_fx.log.size()).is_equal(8)
	assert_array(_texts(_fx.log, "en_GB-cori-medium")).contains_exactly_in_any_order(items)
	assert_array(_texts(_fx.log, "en_US-kristin-medium")).contains_exactly_in_any_order(items)
	for r: Dictionary in _fx.log:
		if r["voice"] == "en_GB-cori-medium":
			assert_dict(r["settings"]).is_equal(
				{"length_scale": 1.05, "noise_scale": 0.333, "noise_w_scale": 0.333}
			)
		else:
			assert_dict(r["settings"]).is_empty()
	var cori: SpyVoiceSynth = _fx.spies["en_GB-cori-medium"]
	assert_dict(cori.started_with).contains_keys(["length_scale"])
	assert_bool(_svc.closed_set_done()).is_false()
	_svc._process(0.0)
	assert_array(ready).has_size(1)
	assert_str(ready[0][0]).is_equal("en")
	assert_bool(_svc.start_ms.has("en")).is_true()
	assert_int(_svc.name_clip("computer", "Viper Three").size()).is_equal(
		"Viper Three".length() * SpyVoiceSynth.LEN_PER_CHAR * 2
	)
	assert_int(_svc.name_clip("npc", "Mara Quill").size()).is_greater(0)
	assert_int(_net.voice.size()).is_equal(0)
	assert_int(_net.events.size()).is_equal(0)


# FT: FT-AUD-018, FT-AUD-019
# A language whose roles share one voice (Italian) runs one process for it, which then
# sees every item twice: once per role, with that role's settings.
func test_a_shared_voice_gets_the_closed_set_for_both_roles() -> void:
	_svc.start_session("it", CLOSED)
	assert_int(_fx.spies.size()).is_equal(1)
	var serena: SpyVoiceSynth = _fx.spies["it_IT-serena-medium"]
	assert_int(_texts(_fx.log, "it_IT-serena-medium").size()).is_equal(8)
	assert_dict(serena.started_with).is_empty()
	var slow: Array = _fx.log.filter(
		func(r: Dictionary) -> bool: return r["settings"].has("length_scale")
	)
	assert_int(slow.size()).is_equal(4)


# FT: FT-AUD-018, FT-AUD-019
# With an adapter that only takes process-wide settings (the binary), Italian's roles
# share the voice with equal effective settings: each name is synthesised once, as one
# whole clip, and both roles use it.
func test_a_shared_voice_with_equal_settings_shares_the_names() -> void:
	_fx.per_request_settings = false
	_start("it")
	var serena: Array = _texts(_fx.log, "it_IT-serena-medium")
	assert_array(serena).contains_exactly_in_any_order(
		["Valiant", "Viper Three", "Ghost One", "Mara Quill"]
	)
	for r: Dictionary in _fx.log:
		assert_bool(r["whole"]).is_true()
	var clip: PackedByteArray = _svc.name_clip("npc", "Mara Quill")
	assert_int(clip.size()).is_equal("Mara Quill".length() * SpyVoiceSynth.LEN_PER_CHAR * 2)
	assert_bool(_svc.name_clip("computer", "Mara Quill") == clip).is_true()
	_svc.say("npc.hail_patrol", {"ship": "Valiant", "npc": "Mara Quill"}, PackedInt32Array([1]))
	assert_int(_fx.log.size()).is_equal(4)
	assert_array(Array(_fx.decode("it", "npc", _net.voice[0][1]["pcm"]))).is_equal(
		["name:7", "seg:npc.hail_patrol:1", "name:10", "seg:npc.hail_patrol:2"]
	)


# FT: FT-AUD-003, FT-AUD-018, FT-ARC-019
# A slotted line with names and numbers needs no synthesis: one voice_line event with
# the text and coalescing key filled, then one stitched VOICE message (part 0, last)
# holding segment, name and number clips in speaking order.
func test_slotted_lines_are_stitched_without_synthesis() -> void:
	_start()
	_fx.log.clear()
	var clip: int = _svc.say("computer.contact", CONTACT, PackedInt32Array([7]))
	_svc._process(0.0)
	assert_int(_fx.log.size()).is_equal(0)
	assert_array(Array(_net.order)).is_equal(["event", "voice"])
	var e: Array = _net.events[0]
	assert_array(Array(e[0])).is_equal([7])
	assert_str(e[2]).is_equal(VoiceService.EVENT_VOICE_LINE)
	var p: Dictionary = e[3]
	assert_int(p["clip"]).is_equal(clip)
	assert_str(p["line"]).is_equal("computer.contact")
	assert_str(p["text"]).is_equal("Contact Viper Three, bearing 342, range 18 kilometres.")
	assert_str(p["coalesce"]).is_equal("contact:Viper Three")
	assert_str(p["role"]).is_equal("computer")
	assert_int(p["priority"]).is_equal(1)
	assert_int(p["max_age_ms"]).is_equal(4000)
	assert_bool(p["resume"]).is_true()
	assert_bool(p["audio"]).is_true()
	assert_bool(p["local"]).is_false()
	var v: Dictionary = _net.voice[0][1]
	assert_int(_net.voice[0][0]).is_equal(7)
	assert_int(v["clip"]).is_equal(clip)
	assert_int(v["part"]).is_equal(0)
	assert_bool(v["last"]).is_true()
	assert_int(v["rate"]).is_equal(SpyVoiceSynth.RATE)
	(
		assert_array(Array(_fx.decode("en", "computer", v["pcm"])))
		. is_equal(
			[
				"seg:computer.contact:0",
				"name:11",
				"seg:computer.contact:1",
				"num:3",
				"num:hundred",
				"num:and",
				"num:42",
				"seg:computer.contact:2",
				"num:18",
				"seg:computer.contact:3",
			]
		)
	)
	# The 70 ms gap between pieces.
	var gap: int = PcmStitch.GAP_MS * SpyVoiceSynth.RATE / 1000
	var first_end: int = VoiceFixture.CLIP_SAMPLES
	assert_int((v["pcm"] as PackedByteArray).decode_s16(first_end * 2)).is_equal(0)
	assert_int((v["pcm"] as PackedByteArray).decode_s16((first_end + gap) * 2)).is_not_equal(0)


# FT: FT-AUD-018
# Number slots use the slot's gender per language: pt_PT "duas" and "duzentas" only where
# the counted noun is feminine, Italian "una"; names are the NPC voice's cached clips.
func test_stitched_numbers_follow_the_slot_gender() -> void:
	_start("pt_PT")
	_svc.say("npc.trade_offer", {"count": 2, "price": 200}, PackedInt32Array([1]))
	var pcm: PackedByteArray = _net.voice[0][1]["pcm"]
	(
		assert_array(Array(_fx.decode("pt_PT", "npc", pcm)))
		. is_equal(
			[
				"seg:npc.trade_offer:0",
				"num:f2",
				"seg:npc.trade_offer:1",
				"num:c2",
				"seg:npc.trade_offer:2",
			]
		)
	)
	assert_str(_net.events[0][3]["text"]).is_equal(
		"Posso ceder-lhe 2 peças sobresselentes por 200 créditos."
	)
	_svc.say("computer.enemies_remaining", {"count": 1}, PackedInt32Array([1]))
	pcm = _net.voice[1][1]["pcm"]
	assert_array(Array(_fx.decode("pt_PT", "computer", pcm))).is_equal(
		["seg:computer.enemies_remaining:0", "num:f1", "seg:computer.enemies_remaining:1"]
	)
	_svc.stop()
	_start("it")
	_svc.say("computer.enemies_remaining", {"count": 1}, PackedInt32Array([1]))
	pcm = _net.voice[2][1]["pcm"]
	assert_array(Array(_fx.decode("it", "computer", pcm))).is_equal(
		["seg:computer.enemies_remaining:0", "num:f1", "seg:computer.enemies_remaining:1"]
	)
	_svc.say("npc.hail_patrol", {"ship": "Valiant", "npc": "Mara Quill"}, PackedInt32Array([1]))
	pcm = _net.voice[3][1]["pcm"]
	assert_array(Array(_fx.decode("it", "npc", pcm))).is_equal(
		["name:7", "seg:npc.hail_patrol:1", "name:10", "seg:npc.hail_patrol:2"]
	)


# FT: FT-AUD-010
# Slots are filled in one pass: a value that looks like a slot is spoken as it is, not
# filled again.
func test_slot_values_are_not_filled_again() -> void:
	var line: Dictionary = DialogueLines.load_dir().line("npc.hail_patrol")
	var template: String = line["text"]["en"]
	assert_str(DialogueLines.fill(line, template, {"ship": "{npc}", "npc": "Mara"})).is_equal(
		"{npc}, this is Mara of the patrol. Hold your course."
	)
	assert_str(DialogueLines.fill(line, template, {"ship": "Hawk", "npc": "{ship}"})).is_equal(
		"Hawk, this is {ship} of the patrol. Hold your course."
	)


# FT: FT-AUD-003, FT-ARC-019
# A line without slots is local: the event only (the client plays its own prerendered
# clip), no synthesis and no VOICE message.
func test_local_lines_send_the_event_only() -> void:
	_start()
	_fx.log.clear()
	_svc.say("computer.hull_critical", {}, PackedInt32Array([2, 3]))
	_svc._process(0.0)
	assert_int(_fx.log.size()).is_equal(0)
	assert_int(_net.voice.size()).is_equal(0)
	var p: Dictionary = _net.events[0][3]
	assert_array(Array(_net.events[0][0])).is_equal([2, 3])
	assert_bool(p["local"]).is_true()
	assert_bool(p["audio"]).is_true()
	assert_str(p["text"]).is_equal("Hull critical.")
	assert_int(p["priority"]).is_equal(0)


# FT: FT-AUD-003, FT-ARC-019, FT-AUD-019
# Free text makes exactly one synthesis request, streamed as one VOICE part per sentence
# after the event; the last part ends the clip.
func test_free_text_is_one_request_streamed_per_sentence() -> void:
	_start()
	_fx.log.clear()
	var clip: int = _svc.say_free(
		"Hold position. We are coming about!", "npc", 2, PackedInt32Array([4])
	)
	assert_int(_fx.log.size()).is_equal(1)
	assert_str(_fx.log[0]["voice"]).is_equal("en_US-kristin-medium")
	assert_int(_svc.free_queued()).is_equal(1)
	_svc._process(0.0)
	assert_array(Array(_net.order)).is_equal(["event", "voice", "voice"])
	var p: Dictionary = _net.events[0][3]
	assert_int(p["clip"]).is_equal(clip)
	assert_str(p["line"]).is_empty()
	assert_bool(p["audio"]).is_true()
	assert_bool(p["local"]).is_false()
	assert_int(p["max_age_ms"]).is_equal(VoiceService.DEFAULT_FREE_MAX_AGE_MS)
	var parts: Array = _net.voice.map(func(v: Array) -> Array: return [v[1]["part"], v[1]["last"]])
	assert_array(parts).is_equal([[0, false], [1, true]])
	assert_int(_svc.free_queued()).is_equal(0)


# FT: FT-AUD-015
# D110: with more than 4 free-text lines queued for synthesis, a new one is subtitles
# only (its event says audio false, nothing is requested); once the queue drains, audio
# comes back.
func test_more_than_four_queued_free_lines_are_subtitles_only() -> void:
	_fx.hold = true
	_start_held()
	_fx.log.clear()
	var audio: Array = []
	for i: int in 6:
		_svc.say_free("Line %d." % i, "computer", 1, PackedInt32Array([1]))
		audio.append(_net.events[i][3]["audio"])
	assert_array(audio).is_equal([true, true, true, true, true, false])
	assert_int(_fx.log.size()).is_equal(5)
	assert_int(_svc.stats["free_subtitles_only"]).is_equal(1)
	(_fx.spies["en_GB-cori-medium"] as SpyVoiceSynth).release()
	_svc._process(0.0)
	assert_int(_svc.free_queued()).is_equal(0)
	_svc.say_free("Again.", "computer", 1, PackedInt32Array([1]))
	assert_bool(_net.events[6][3]["audio"]).is_true()


# FT: FT-AUD-015, FT-AUD-018
# A synth that hands over nothing for job_timeout_ms fails its jobs: the closed set
# completes without the names, a free line's clip ends with an empty last part, and the
# D110 count drops.
func test_stalled_jobs_time_out() -> void:
	_fx.hold = true
	_svc.job_timeout_ms = 50
	_svc.start_session("en", CLOSED)
	_svc.say_free("Hold position. Now.", "npc", 2, PackedInt32Array([4]))
	_svc._process(0.0)
	assert_bool(_svc.closed_set_done()).is_false()
	assert_int(_svc.free_queued()).is_equal(1)
	OS.delay_msec(120)
	_svc._process(0.0)
	assert_bool(_svc.closed_set_done()).is_true()
	assert_int(_svc.free_queued()).is_equal(0)
	assert_int(_svc.name_clip("npc", "Mara Quill").size()).is_equal(0)
	assert_int(_net.voice.size()).is_equal(1)
	var v: Dictionary = _net.voice[0][1]
	assert_bool(v["last"]).is_true()
	assert_int((v["pcm"] as PackedByteArray).size()).is_equal(0)
	assert_int(_svc.stats["synth_errors"]).is_equal(9)
	# Late parts of a timed-out job are ignored.
	for spy: SpyVoiceSynth in _fx.spies.values():
		spy.release()
	_svc._process(0.0)
	assert_int(_net.voice.size()).is_equal(1)


# FT: FT-AUD-015, FT-M1-012
# A run reset flushes the lines not sent yet: free text being synthesised sends no VOICE
# afterwards and the D110 count is back to 0; the synths and the closed set stay.
func test_flush_drops_queued_lines_and_keeps_the_session() -> void:
	_fx.hold = true
	_start_held()
	_svc.say_free("Old run. Line one.", "computer", 1, PackedInt32Array([1]))
	_svc.say_free("Old run. Line two.", "npc", 1, PackedInt32Array([1]))
	assert_int(_svc.free_queued()).is_equal(2)
	_svc.flush_lines()
	assert_int(_svc.free_queued()).is_equal(0)
	for spy: SpyVoiceSynth in _fx.spies.values():
		spy.release()
	_svc._process(0.0)
	assert_array(_net.voice).is_empty()
	assert_bool(_svc.has_voice("computer")).is_true()
	assert_bool(_svc.closed_set_done()).is_true()


# FT: FT-AUD-003, FT-AUD-015
# Free text is cut to MAX_FREE_CHARS at a space for synthesis; the subtitle keeps it all.
func test_long_free_text_is_cut_for_synthesis() -> void:
	_start()
	_fx.log.clear()
	var text: String = "word ".repeat(100) + "end."
	_svc.say_free(text, "npc", 2, PackedInt32Array([4]))
	var spoken: String = _fx.log[0]["text"]
	assert_int(spoken.length()).is_less_equal(VoiceService.MAX_FREE_CHARS)
	assert_bool(spoken.ends_with("word")).is_true()
	assert_str(_net.events[0][3]["text"]).is_equal(text)


# FT: FT-AUD-018
# A name missing from the closed set is synthesised once and cached (a counted miss);
# the stitched clip waits for it, and the next line with that name needs no synthesis.
func test_a_closed_set_miss_is_synthesised_once_and_cached() -> void:
	_fx.hold = true
	_start_held()
	_fx.log.clear()
	var args: Dictionary = {"callsign": "Nomad Six", "bearing": 5, "range": 7}
	_svc.say("computer.contact", args, PackedInt32Array([1]))
	assert_int(_fx.log.size()).is_equal(1)
	assert_str(_fx.log[0]["text"]).is_equal("Nomad Six")
	assert_int(_svc.stats["closed_set_misses"]).is_equal(1)
	_svc._process(0.0)
	assert_int(_net.voice.size()).is_equal(0)
	(_fx.spies["en_GB-cori-medium"] as SpyVoiceSynth).release()
	_svc._process(0.0)
	assert_int(_net.voice.size()).is_equal(1)
	assert_str(_fx.decode("en", "computer", _net.voice[0][1]["pcm"])[1]).is_equal("name:9")
	_svc.say("computer.contact", args, PackedInt32Array([1]))
	assert_int(_fx.log.size()).is_equal(1)
	assert_int(_svc.stats["closed_set_misses"]).is_equal(1)
	assert_int(_net.voice.size()).is_equal(2)


# FT: FT-AUD-014, FT-AUD-010
# pt_PT's voice is development only (D105): without dev voices every line is subtitles
# only, nothing is synthesised and the closed set is ready at once.
func test_a_dev_only_language_is_subtitles_only_in_releases() -> void:
	_svc.allow_dev_voices = false
	_start("pt_PT")
	assert_int(_fx.spies.size()).is_equal(0)
	_svc.say("computer.hull_critical", {}, PackedInt32Array([1]))
	_svc.say("computer.contact", CONTACT, PackedInt32Array([1]))
	_svc.say_free("Olá.", "npc", 2, PackedInt32Array([1]))
	_svc._process(0.0)
	assert_int(_net.events.size()).is_equal(3)
	for e: Array in _net.events:
		assert_bool(e[3]["audio"]).is_false()
	assert_str(_net.events[1][3]["text"]).is_equal(
		"Contacto Viper Three, rumo 342, distância 18 quilómetros."
	)
	assert_int(_net.voice.size()).is_equal(0)
	assert_int(_fx.log.size()).is_equal(0)


# FT: FT-AUD-010
# A voice whose model is missing makes its role's lines that need it subtitles only; the
# other role still speaks.
func test_a_missing_voice_model_is_subtitles_only() -> void:
	_fx.missing = ["en_US-kristin-medium"]
	_start()
	assert_bool(_svc.has_voice("npc")).is_false()
	_svc.say("npc.hail_trader", {"npc": "Mara Quill"}, PackedInt32Array([1]))
	_svc.say_free("Hello.", "npc", 2, PackedInt32Array([1]))
	_svc.say("computer.shields_low", {"pct": 40}, PackedInt32Array([1]))
	_svc._process(0.0)
	assert_bool(_net.events[0][3]["audio"]).is_false()
	assert_bool(_net.events[1][3]["audio"]).is_false()
	assert_bool(_net.events[2][3]["audio"]).is_true()
	assert_int(_net.voice.size()).is_equal(1)


# The routing hooks pick the audience; unset hooks give an empty one and send nothing.
func test_routing_hooks_choose_the_audience() -> void:
	_start()
	_svc.say_npc("trader_1", "npc.hail_trader", {"npc": "Mara Quill"})
	_svc.say_computer_free(0, PackedStringArray(["helm"]), "Course laid in.")
	assert_int(_net.events.size()).is_equal(0)
	_svc.npc_audience = func(npc_id: String) -> PackedInt32Array:
		return PackedInt32Array([5]) if npc_id == "trader_1" else PackedInt32Array()
	_svc.computer_audience = func(ship: int, stations: PackedStringArray) -> PackedInt32Array:
		return PackedInt32Array([ship + 10]) if stations.has("helm") else PackedInt32Array()
	_svc.tick_source = func() -> int: return 77
	_svc.say_npc("trader_1", "npc.hail_trader", {"npc": "Mara Quill"})
	_svc.say_computer(1, PackedStringArray(["helm"]), "computer.jump_ready")
	_svc.say_computer_free(2, PackedStringArray(["helm"]), "Course laid in.")
	_svc._process(0.0)
	var to: Array = _net.events.map(func(e: Array) -> Array: return Array(e[0]))
	assert_array(to).is_equal([[5], [11], [12]])
	assert_int(_net.events[0][1]).is_equal(77)
