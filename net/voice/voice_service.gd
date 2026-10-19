class_name VoiceService
extends Node
## The host's voice service (E10, spec §9, audio/README.md): composed next to NetServer,
## it turns spoken lines into one reliable `voice_line` event for the line's audience
## and, when the host makes the audio, VOICE messages on that audience's voice lane only
## (D85, D101, D152; FT-AUD-019, FT-NET-038).
##
## - Authored lines without slots are `local`: clients play `line:<id>` from their own
##   ClipLibrary; the host sends the event only, no synthesis, no VOICE.
## - Slotted lines are stitched from this host's ClipLibrary (`seg:<id>:<k>`, `num:<key>`
##   from NumberWords) and the closed-set names cached at Start; one VOICE message, part
##   0, last (FT-AUD-018). No synthesis unless a name is missing from the cache (a
##   closed-set miss, synthesised once and cached).
## - Free text is synthesised at runtime, one VOICE part per sentence as Piper finishes
##   it (FT-AUD-003, FT-AUD-015). With more than MAX_QUEUED_FREE_LINES free-text lines
##   already queued, a new one is subtitles only (D110).
##
## Synthesis runs in one persistent Piper process per distinct runtime voice of the
## session language, each behind a VoiceSynth (synth_factory) with its own worker
## thread; _process() only takes finished parts and posts them, so the sim thread never
## waits on a pipe (FT-AUD-019, FT-ARC-019). A language whose voices are `dev_only`
## while dev voices aren't allowed (pt_PT in releases, D105), or a voice with no model,
## gives subtitles only (audio false) and nothing else changes. No robotic filter here:
## the client applies it on its VoiceComputer bus (FT-AUD-004, D153).
##
## Routing hooks for #10's main lead (D39):
## - `npc_audience: Callable(npc_id: String) -> PackedInt32Array`: the session holding
##   that NPC's conversation claim (FT-AUD-005). Used by say_npc() and say_npc_free().
## - `computer_audience: Callable(ship: int, stations: PackedStringArray) ->
##   PackedInt32Array`: the sessions on that ship holding any of those stations
##   (FT-AUD-006). Used by say_computer() and say_computer_free().
## Both default to an empty audience with a warning. `tick_source: Callable() -> int`
## gives the events' tick (0 when unset).

## Emitted when the session's closed set is synthesised and cached (FT-AUD-018).
signal closed_set_ready(lang: String, elapsed_ms: int)

## D110, FT-AUD-015: free-text lines queued for synthesis (requested, not finished,
## across voices) beyond which a new free-text line is subtitles only. PROVISIONAL.
const MAX_QUEUED_FREE_LINES: int = 4
## Max age of a free-text line on the client's voice bus (FT-AUD-008). PROVISIONAL.
const DEFAULT_FREE_MAX_AGE_MS: int = 6000
const ROLES: PackedStringArray = ["computer", "npc"]
const EVENT_VOICE_LINE: String = "voice_line"
const DEFAULT_VOICES: String = "res://content/voices.json"

var transport: NetTransport
## Callable(voice_name: String) -> VoiceSynth (not started) or null; ServerMain passes
## PiperSetup.make. Unset: no voices, every line subtitles only.
var synth_factory: Callable
var npc_audience: Callable = _no_npc_audience
var computer_audience: Callable = _no_computer_audience
var tick_source: Callable = Callable()
## Where the prerendered clips are (ClipLibrary.load_dir), the dialogue JSON and voices.
var prerender_dir: String = ClipLibrary.DEFAULT_DIR
var dialogue_dir: String = DialogueLines.DEFAULT_DIR
var voices_path: String = DEFAULT_VOICES
## Whether `dev_only` voices (D105) may speak: debug builds only by default.
var allow_dev_voices: bool = OS.is_debug_build()
## The session language and its data, from start_session().
var lang: String = ""
var library: ClipLibrary = ClipLibrary.new()
var dialogue: DialogueLines = DialogueLines.new()
## Start time per language in ms, start_session() to closed_set_ready (FT-AUD-018).
var start_ms: Dictionary = {}
## Counters: closed_set_misses, free_lines, free_subtitles_only (D110), voice_messages,
## synth_errors.
var stats: Dictionary = {
	"closed_set_misses": 0,
	"free_lines": 0,
	"free_subtitles_only": 0,
	"voice_messages": 0,
	"synth_errors": 0,
}

var _voices: Dictionary = {}
var _lang_allowed: bool = false
## voice name -> VoiceSynth; role -> VoiceSynth; role -> settings.
var _synths: Dictionary = {}
var _role_synth: Dictionary = {}
var _role_settings: Dictionary = {}
## role -> {name text -> trimmed PCM}; role -> {name text -> request id in flight}.
var _names: Dictionary = {}
var _names_in_flight: Dictionary = {}
## request id -> job: {"kind": "name", role, text, closed, pcm, rate} or {"kind": "free",
## clip, audience}.
var _jobs: Dictionary = {}
## Stitched lines waiting for a name: {clip, role, rate, audience, items}.
var _waiting: Array[Dictionary] = []
var _next_id: int = 1
var _free_queued: int = 0
var _closed_pending: int = 0
var _closed_started_us: int = 0
var _closed_reported: bool = true


func _init(net: NetTransport = null, factory: Callable = Callable()) -> void:
	transport = net
	synth_factory = factory


## Starts the session's voice: loads lang's prerendered clips and dialogue, starts one
## synth per distinct runtime voice, and synthesises every closed-set name once per role
## in that role's voice and settings (FT-AUD-018); closed_set_ready follows. `closed_set`
## holds "ship_names", "callsigns" and "npc_names" (Arrays of String).
func start_session(language: String, closed_set: Dictionary) -> void:
	stop()
	lang = language
	_closed_started_us = Time.get_ticks_usec()
	_closed_reported = false
	library = ClipLibrary.load_dir(prerender_dir, lang)
	dialogue = DialogueLines.load_dir(dialogue_dir)
	_load_voices()
	for role: String in ROLES:
		_names[role] = {}
		_names_in_flight[role] = {}
	if not _lang_allowed:
		return
	var by_voice: Dictionary = {}
	var spec: Dictionary = _voices.get("languages", {}).get(lang, {})
	for role: String in ROLES:
		var voice: String = str((spec.get(role, {}) as Dictionary).get("runtime", ""))
		if voice == "":
			continue
		if not by_voice.has(voice):
			by_voice[voice] = []
		(by_voice[voice] as Array).append(role)
	for voice: String in by_voice:
		var synth: VoiceSynth = synth_factory.call(voice) if synth_factory.is_valid() else null
		if synth == null:
			continue
		var roles: Array = by_voice[voice]
		# Process-wide settings for adapters that can't take them per request: the
		# role's when one role uses the voice, else Piper's defaults.
		var defaults: Dictionary = _role_settings[roles[0]] if roles.size() == 1 else {}
		if synth.start(defaults) != OK:
			push_warning("voice %s failed to start; its lines are subtitles only" % voice)
			continue
		_synths[voice] = synth
		for role: String in roles:
			_role_synth[role] = synth
	var items: PackedStringArray = PackedStringArray()
	for group: String in ["ship_names", "callsigns", "npc_names"]:
		for item: Variant in closed_set.get(group, []):
			if not items.has(str(item)) and str(item) != "":
				items.append(str(item))
	for role: String in ROLES:
		if not _role_synth.has(role):
			continue
		for item: String in items:
			_request_name(role, item, true)


## Says an authored line to `audience` (session ids); returns its clip id, or -1 for an
## unknown line. Sends the `voice_line` event (text and coalescing key in the session
## language, slots filled from args); a slotted line's stitched clip follows as one
## VOICE message.
func say(line_id: String, args: Dictionary, audience: PackedInt32Array) -> int:
	var line: Dictionary = dialogue.line(line_id)
	if line.is_empty():
		push_error("VoiceService: unknown line %s" % line_id)
		return -1
	var clip: int = _new_id()
	var role: String = str(line.get("role", "computer"))
	var template: String = str((line.get("text", {}) as Dictionary).get(lang, ""))
	var local: bool = (line.get("slots", {}) as Dictionary).is_empty()
	var audio: bool = false
	var items: Array = []
	if local:
		audio = _lang_allowed and library.has_clip(role, "line:" + line_id)
	elif _lang_allowed and library.has_role(role) and not audience.is_empty():
		items = _stitch_items(line, template, args, role)
		audio = not items.is_empty()
	var event: Dictionary = {
		"clip": clip,
		"line": line_id,
		"text": DialogueLines.fill(line, template, args),
		"role": role,
		"priority": int(line.get("priority", 1)),
		"max_age_ms": int(line.get("max_age_ms", DEFAULT_FREE_MAX_AGE_MS)),
		"coalesce": DialogueLines.fill(line, str(line.get("coalesce", "")), args),
		"resume": bool(line.get("resume", false)),
		"audio": audio,
		"local": local,
	}
	_post_event(audience, event)
	if audio and not local and not audience.is_empty():
		_waiting.append(
			{
				"clip": clip,
				"role": role,
				"rate": library.rate(role),
				"audience": audience,
				"items": items
			}
		)
		_flush_waiting()
	return clip


## Says free text in a role's voice: synthesised now and streamed per sentence
## (FT-AUD-003); subtitles only when the voice is unavailable or more than
## MAX_QUEUED_FREE_LINES free-text lines are already queued (D110, FT-AUD-015).
func say_free(
	text: String,
	role: String,
	priority: int,
	audience: PackedInt32Array,
	max_age_ms: int = DEFAULT_FREE_MAX_AGE_MS
) -> int:
	var clip: int = _new_id()
	stats["free_lines"] += 1
	var audio: bool = _lang_allowed and _role_synth.has(role) and not audience.is_empty()
	if audio and _free_queued > MAX_QUEUED_FREE_LINES:
		audio = false
		stats["free_subtitles_only"] += 1
	var event: Dictionary = {
		"clip": clip,
		"line": "",
		"text": text,
		"role": role,
		"priority": priority,
		"max_age_ms": max_age_ms,
		"coalesce": "",
		"resume": false,
		"audio": audio,
		"local": false,
	}
	_post_event(audience, event)
	if audio:
		_jobs[clip] = {"kind": "free", "clip": clip, "audience": audience}
		_free_queued += 1
		(_role_synth[role] as VoiceSynth).request(clip, text, _role_settings.get(role, {}))
	return clip


## An NPC line to the client holding that NPC's conversation (FT-AUD-005).
func say_npc(npc_id: String, line_id: String, args: Dictionary = {}) -> int:
	return say(line_id, args, npc_audience.call(npc_id))


## A ship-computer line to the clients holding those stations (FT-AUD-006).
func say_computer(
	ship: int, stations: PackedStringArray, line_id: String, args: Dictionary = {}
) -> int:
	return say(line_id, args, computer_audience.call(ship, stations))


func say_npc_free(
	npc_id: String, text: String, priority: int = 2, max_age_ms: int = DEFAULT_FREE_MAX_AGE_MS
) -> int:
	return say_free(text, "npc", priority, npc_audience.call(npc_id), max_age_ms)


func say_computer_free(
	ship: int,
	stations: PackedStringArray,
	text: String,
	priority: int = 1,
	max_age_ms: int = DEFAULT_FREE_MAX_AGE_MS
) -> int:
	return say_free(text, "computer", priority, computer_audience.call(ship, stations), max_age_ms)


## Free-text lines requested and not yet finished (D110).
func free_queued() -> int:
	return _free_queued


## True once the closed set of the current session is cached.
func closed_set_done() -> bool:
	return _closed_reported


## True when `role` has a voice in this session (else its lines are subtitles only).
func has_voice(role: String) -> bool:
	return _lang_allowed and _role_synth.has(role)


## The cached closed-set name clip for a role, or an empty array.
func name_clip(role: String, text: String) -> PackedByteArray:
	return (_names.get(role, {}) as Dictionary).get(text, PackedByteArray())


## Stops every synth; the session's voice is off until the next start_session().
func stop() -> void:
	for synth: VoiceSynth in _synths.values():
		synth.stop()
	_synths.clear()
	_role_synth.clear()
	_jobs.clear()
	_waiting.clear()
	_free_queued = 0
	_closed_pending = 0
	_closed_reported = true


func _process(_delta: float) -> void:
	for synth: VoiceSynth in _synths.values():
		for part: Dictionary in synth.take_parts():
			_on_part(part)
	if not _waiting.is_empty():
		_flush_waiting()
	if not _closed_reported and _closed_pending == 0 and lang != "":
		_closed_reported = true
		var ms: int = (Time.get_ticks_usec() - _closed_started_us) / 1000
		start_ms[lang] = ms
		closed_set_ready.emit(lang, ms)


func _exit_tree() -> void:
	stop()


func _load_voices() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(voices_path))
	_voices = data if data is Dictionary else {}
	var spec: Variant = (_voices.get("languages", {}) as Dictionary).get(lang)
	_lang_allowed = spec is Dictionary and (allow_dev_voices or not spec.get("dev_only", false))
	if spec is Dictionary and not _lang_allowed:
		push_warning("voices for %s are development only: subtitles only (D105)" % lang)
	_role_settings.clear()
	for role: String in ROLES:
		var all: Dictionary = (_voices.get("roles", {}) as Dictionary).get(role, {})
		var settings: Dictionary = {}
		for key: String in VoiceSynth.SETTING_KEYS:
			if all.has(key):
				settings[key] = all[key]
		_role_settings[role] = settings


## The stitched line as a list of PCM pieces and pending names ([role, name]), in
## speaking order; [] when the line can't be stitched (subtitles only).
func _stitch_items(line: Dictionary, template: String, args: Dictionary, role: String) -> Array:
	var items: Array = []
	var pieces: PackedStringArray = DialogueLines.pieces(template)
	var slots: PackedStringArray = DialogueLines.slot_order(template)
	var id: String = line["id"]
	for k: int in pieces.size():
		var seg: Dictionary = library.clip(role, "seg:%s:%d" % [id, k])
		if not seg.is_empty():
			items.append(seg["pcm"])
		elif _has_letter(pieces[k]):
			push_warning("VoiceService: no clip seg:%s:%d in %s" % [id, k, lang])
		if k >= slots.size():
			continue
		var slot: String = slots[k]
		var kind: String = DialogueLines.slot_kind(line, slot)
		if kind == "number":
			var fem: bool = DialogueLines.is_feminine(line, slot, lang)
			for key: String in NumberWords.compose(int(args.get(slot, 0)), lang, fem):
				var frag: Dictionary = library.clip(role, "num:" + key)
				if frag.is_empty():
					push_warning("VoiceService: no clip num:%s in %s" % [key, lang])
				else:
					items.append(frag["pcm"])
		elif DialogueLines.NAME_KINDS.has(kind):
			var text: String = str(args.get(slot, ""))
			if text == "":
				continue
			if not _role_synth.has(role):
				return []
			if not (_names[role] as Dictionary).has(text):
				if not (_names_in_flight[role] as Dictionary).has(text):
					stats["closed_set_misses"] += 1
					_request_name(role, text, false)
			items.append([role, text])
	return items


## Sends every waiting stitched line whose names are all cached (or failed).
func _flush_waiting() -> void:
	var still: Array[Dictionary] = []
	for w: Dictionary in _waiting:
		var parts: Array[PackedByteArray] = []
		var ready: bool = true
		for item: Variant in w["items"]:
			if item is PackedByteArray:
				parts.append(item)
				continue
			var role: String = item[0]
			var text: String = item[1]
			if (_names[role] as Dictionary).has(text):
				parts.append(_names[role][text])
			elif (_names_in_flight[role] as Dictionary).has(text):
				ready = false
				break
		if not ready:
			still.append(w)
			continue
		_send_voice(w["audience"], w["clip"], w["rate"], PcmStitch.join(parts, w["rate"]), 0, true)
	_waiting = still


func _request_name(role: String, text: String, closed: bool) -> void:
	var id: int = _new_id()
	_jobs[id] = {
		"kind": "name", "role": role, "text": text, "closed": closed, "pcm": PackedByteArray()
	}
	_names_in_flight[role][text] = id
	if closed:
		_closed_pending += 1
	(_role_synth[role] as VoiceSynth).request(id, text, _role_settings.get(role, {}))


func _on_part(part: Dictionary) -> void:
	var job: Dictionary = _jobs.get(part["id"], {})
	if job.is_empty():
		return
	if part["error"] != "":
		stats["synth_errors"] += 1
	if job["kind"] == "free":
		_send_voice(
			job["audience"], job["clip"], part["rate"], part["pcm"], part["part"], part["last"]
		)
		if part["last"]:
			_jobs.erase(part["id"])
			_free_queued -= 1
		return
	# PackedByteArray is a value type: store the joined copy back.
	job["pcm"] = (job["pcm"] as PackedByteArray) + (part["pcm"] as PackedByteArray)
	if not part["last"]:
		return
	_jobs.erase(part["id"])
	var role: String = job["role"]
	(_names_in_flight[role] as Dictionary).erase(job["text"])
	if job["closed"]:
		_closed_pending -= 1
	if part["error"] == "":
		var pcm: PackedByteArray = PcmStitch.normalise(PcmStitch.trim(job["pcm"], part["rate"]))
		if part["rate"] != library.rate(role) and library.has_role(role):
			push_warning(
				(
					"voice %s: name rate %d differs from the prerendered %d"
					% [role, part["rate"], library.rate(role)]
				)
			)
		_names[role][job["text"]] = pcm


func _send_voice(
	audience: PackedInt32Array, clip: int, rate: int, pcm: PackedByteArray, part: int, last: bool
) -> void:
	var msg: PackedByteArray = NetProtocol.encode(
		NetProtocol.Type.VOICE, {"clip": clip, "rate": rate, "pcm": pcm, "part": part, "last": last}
	)
	for session: int in audience:
		transport.post_voice(session, msg)
	stats["voice_messages"] += 1


func _post_event(audience: PackedInt32Array, payload: Dictionary) -> void:
	if audience.is_empty():
		return
	var tick: int = int(tick_source.call()) if tick_source.is_valid() else 0
	transport.post_event(audience, tick, EVENT_VOICE_LINE, payload)


func _new_id() -> int:
	var id: int = _next_id
	_next_id += 1
	return id


static func _has_letter(text: String) -> bool:
	for c: String in text:
		if c.to_lower() != c.to_upper():
			return true
	return false


static func _no_npc_audience(npc_id: String) -> PackedInt32Array:
	push_warning("VoiceService.npc_audience is not set; NPC %s's line goes nowhere" % npc_id)
	return PackedInt32Array()


static func _no_computer_audience(ship: int, stations: PackedStringArray) -> PackedInt32Array:
	push_warning(
		"VoiceService.computer_audience is not set; ship %d %s hears nothing" % [ship, stations]
	)
	return PackedInt32Array()
