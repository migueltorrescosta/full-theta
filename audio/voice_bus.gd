class_name VoiceBus
extends RefCounted
## The client's voice queue (spec §9.3): pure logic with no audio and no scene tree, the
## time passed in as milliseconds, so it is unit-testable (FT-AUD-011). Lines come from
## `voice_line` event payloads (offer) and their audio from VOICE parts (add_part); a
## VoiceSink plays what the bus decides. Playback progress is derived from sample counts
## and rates, so update() must be called with a clock that keeps running.
##
## Rules (FT-AUD-007, FT-AUD-008):
## - P0 > P1 > P2 > P3 (0 is highest). A line starts only once the part it starts from
##   has arrived. Within one priority lines queue FIFO and the head blocks later ones;
##   a lower priority may play while a higher-priority head still waits for audio.
## - A ready line of higher priority preempts the playing one: FADE_MS fade-out, then the
##   preempted line goes back to the queue, to resume from where its fade began, if its
##   `resume` flag is set; otherwise it is dropped. The preemptor starts after the fade.
## - A queued line (not playing) is dropped when older than its max_age_ms (age from
##   offer) or when a newer line with the same non-empty coalescing key is offered.
## - A local line (prerendered, played from a file on the client) has one part: an opaque
##   stream handle with a length, ready at once; it plays and resumes by position (ms).
## - Parts play in order and gaplessly (each is pushed as soon as it and its predecessor
##   are there); when the next part is missing at the end of one, the line waits and an
##   underrun is counted. A line starved longer than STALL_MS is dropped.

## PROVISIONAL: fade-out of a preempted line (spec §9.3).
const FADE_MS: int = 80
## PROVISIONAL: parts that arrive before their voice_line event are held this long.
const ORPHAN_MS: int = 5000
## PROVISIONAL: a playing line waiting this long for its next part is dropped.
const STALL_MS: int = 5000

## Drop reasons, in `dropped`.
const EXPIRED: String = "expired"
const COALESCED: String = "coalesced"
const PREEMPTED: String = "preempted"
const STALLED: String = "stalled"

var sink: VoiceSink = VoiceSink.new()
## Underruns: a part ended and the line's next part had not arrived.
var underruns: int = 0
## Lines dropped, in order: {"clip", "line", "reason", "at_ms"}.
var dropped: Array[Dictionary] = []
## Clips played to their last part, in order.
var finished: Array[int] = []

var _queue: Array[_Line] = []  # waiting lines, by offer order
var _current: _Line = null
var _fading: _Line = null
var _fade_end_ms: int = 0
var _orphans: Dictionary = {}  # clip -> {"at_ms": int, "parts": Array[Dictionary]}
var _seq: int = 0


class _Line:
	extends RefCounted
	var clip: int
	var line: String
	var role: String
	var priority: int
	var max_age_ms: int
	var coalesce: String
	var resume: bool
	var offered_ms: int
	var seq: int
	## part index -> {"rate", "pcm"} or, for a local line, {"stream", "ms"} at rate 1000
	var parts: Dictionary = {}
	var last_part: int = -1
	## Where the next start begins: part and sample within it.
	var pos_part: int = 0
	var pos_sample: int = 0
	## Pushed since this start: {"part", "from", "samples", "rate", "start_ms", "end_ms"}.
	var segments: Array[Dictionary] = []
	var pushed_part: int = -1
	var pushed_end_ms: int = 0
	var stalled_since: int = -1

	func ready() -> bool:
		return parts.has(pos_part)

	func complete() -> bool:
		return last_part >= 0 and pushed_part >= last_part


## Queues the line of a voice_line payload. Returns false when it doesn't enter the bus
## (audio false, D110); such a line still supersedes queued lines with its coalescing key.
func offer(payload: Dictionary, now_ms: int) -> bool:
	var key: String = str(payload.get("coalesce", ""))
	if key != "":
		for l: _Line in _queue.duplicate():
			if l.coalesce == key:
				_drop(l, COALESCED, now_ms)
	if not bool(payload.get("audio", true)):
		update(now_ms)
		return false
	var l: _Line = _Line.new()
	l.clip = int(payload.get("clip", -1))
	l.line = str(payload.get("line", ""))
	l.role = str(payload.get("role", "npc"))
	l.priority = clampi(int(payload.get("priority", 3)), 0, 3)
	l.max_age_ms = int(payload.get("max_age_ms", 0))
	l.coalesce = key
	l.resume = bool(payload.get("resume", false))
	l.offered_ms = now_ms
	_seq += 1
	l.seq = _seq
	_queue.append(l)
	if _orphans.has(l.clip):
		for p: Dictionary in _orphans[l.clip]["parts"]:
			_store(l, p)
		_orphans.erase(l.clip)
	update(now_ms)
	return true


## One VOICE part: `part` counts from 0, `last` ends the clip.
func add_part(
	clip: int, part: int, rate: int, pcm: PackedByteArray, last: bool, now_ms: int
) -> void:
	var p: Dictionary = {"part": part, "rate": rate, "pcm": pcm, "last": last}
	var l: _Line = _find(clip, false)
	if l == null and _fading != null and _fading.clip == clip:
		return  # a dropped line still fading out
	if l == null:
		if not _orphans.has(clip):
			_orphans[clip] = {"at_ms": now_ms, "parts": []}
		_orphans[clip]["parts"].append(p)
	else:
		_store(l, p)
		if l == _current:
			_push_ahead(l, now_ms)
	update(now_ms)


## The audio of a local line: `stream` is an opaque handle the sink plays (an AudioStream),
## `length_ms` its duration. Positions in it are milliseconds.
func add_local(clip: int, stream: Object, length_ms: int, now_ms: int) -> void:
	var l: _Line = _find(clip, false)
	if l == null:
		return
	_store(
		l, {"part": 0, "rate": 1000, "pcm": null, "stream": stream, "ms": length_ms, "last": true}
	)
	if l == _current:
		_push_ahead(l, now_ms)
	update(now_ms)


## Advances the bus to `now_ms`: ends fades and finished lines, counts underruns, drops
## expired lines, preempts and starts lines.
func update(now_ms: int) -> void:
	for clip: int in _orphans.keys():
		if now_ms - int(_orphans[clip]["at_ms"]) > ORPHAN_MS:
			_orphans.erase(clip)
	if _fading != null and now_ms >= _fade_end_ms:
		sink.stop(_fading.clip)
		_fading = null
	if _current != null:
		_advance_current(now_ms)
	# FT-AUD-008: only queued lines age out; age counts from the offer.
	for l: _Line in _queue.duplicate():
		if now_ms - l.offered_ms > l.max_age_ms:
			_drop(l, EXPIRED, now_ms)
	var next: _Line = _best_ready()
	if next == null or _fading != null:
		return
	if _current == null:
		_queue.erase(next)
		_start(next, now_ms)
	elif next.priority < _current.priority:
		_preempt(now_ms)  # FT-AUD-007; the preemptor starts once the fade has ended


## The playing line's clip, or -1.
func playing_clip() -> int:
	return _current.clip if _current != null else -1


## The fading line's clip, or -1.
func fading_clip() -> int:
	return _fading.clip if _fading != null else -1


## Waiting clips, in offer order.
func queued_clips() -> Array[int]:
	var out: Array[int] = []
	for l: _Line in _queue:
		out.append(l.clip)
	return out


## Whether the bus still holds anything of `clip` (line state or audio parts).
func holds(clip: int) -> bool:
	return _find(clip) != null or _orphans.has(clip)


## How many audio parts of `clip` the bus still holds.
func held_parts(clip: int) -> int:
	var l: _Line = _find(clip)
	if l != null:
		return l.parts.size()
	return (_orphans[clip]["parts"] as Array).size() if _orphans.has(clip) else 0


## The reason `clip` was dropped, or "" if it wasn't.
func drop_reason(clip: int) -> String:
	for d: Dictionary in dropped:
		if d["clip"] == clip:
			return d["reason"]
	return ""


func _find(clip: int, fading: bool = true) -> _Line:
	if _current != null and _current.clip == clip:
		return _current
	for l: _Line in _queue:
		if l.clip == clip:
			return l
	if fading and _fading != null and _fading.clip == clip:
		return _fading
	return null


func _store(l: _Line, p: Dictionary) -> void:
	var part: int = int(p["part"])
	if part < l.pos_part or l.parts.has(part) or (l.last_part >= 0 and part > l.last_part):
		return
	l.parts[part] = p
	if bool(p["last"]):
		l.last_part = part


## The head of the highest priority whose head is ready (FIFO within a priority).
func _best_ready() -> _Line:
	var heads: Dictionary = {}
	for l: _Line in _queue:
		if not heads.has(l.priority):
			heads[l.priority] = l
	for p: int in range(4):
		if heads.has(p) and (heads[p] as _Line).ready():
			return heads[p]
	return null


func _start(l: _Line, now_ms: int) -> void:
	_current = l
	l.segments.clear()
	l.pushed_part = l.pos_part - 1
	l.pushed_end_ms = now_ms
	l.stalled_since = -1
	sink.begin(l.clip, l.role, int(l.parts[l.pos_part]["rate"]))
	_push_ahead(l, now_ms)


## Pushes every consecutive part that has arrived, each starting where the previous
## one ends (or now, after an underrun).
func _push_ahead(l: _Line, now_ms: int) -> void:
	while l.parts.has(l.pushed_part + 1):
		var part: int = l.pushed_part + 1
		var p: Dictionary = l.parts[part]
		var rate: int = maxi(int(p["rate"]), 1)
		var from: int = l.pos_sample if part == l.pos_part else 0
		var stream: Object = p.get("stream")
		var total: int = (
			int(p["ms"]) if stream != null else (p["pcm"] as PackedByteArray).size() >> 1
		)
		var samples: int = maxi(total - from, 0)
		var start_ms: int = maxi(l.pushed_end_ms, now_ms)
		var end_ms: int = start_ms + ceili(samples * 1000.0 / rate)
		l.segments.append(
			{
				"part": part,
				"from": from,
				"samples": samples,
				"rate": rate,
				"start_ms": start_ms,
				"end_ms": end_ms
			}
		)
		if stream != null:
			sink.play_stream(l.clip, stream, from)
		elif samples > 0:
			sink.push(l.clip, p["pcm"], rate, from)
		l.pushed_part = part
		l.pushed_end_ms = end_ms
		l.stalled_since = -1


func _advance_current(now_ms: int) -> void:
	var l: _Line = _current
	if now_ms < l.pushed_end_ms:
		_trim(l, now_ms)
		return
	if l.complete():
		sink.finish(l.clip)
		finished.append(l.clip)
		l.parts.clear()
		_current = null
		return
	if l.stalled_since < 0:
		underruns += 1
		l.stalled_since = l.pushed_end_ms
	elif now_ms - l.stalled_since > STALL_MS:
		sink.stop(l.clip)
		_current = null
		_record(l, STALLED, now_ms)


## Frees the parts the line has played past.
func _trim(l: _Line, now_ms: int) -> void:
	for s: Dictionary in l.segments:
		if int(s["end_ms"]) <= now_ms:
			l.parts.erase(int(s["part"]))


## Fades the playing line; it resumes later from the fade's start, or is dropped.
func _preempt(now_ms: int) -> void:
	var l: _Line = _current
	_current = null
	_set_position(l, now_ms)
	sink.fade_out(l.clip, FADE_MS)
	_fading = l
	_fade_end_ms = now_ms + FADE_MS
	if l.resume:
		var at: int = 0
		while at < _queue.size() and _queue[at].seq < l.seq:
			at += 1
		_queue.insert(at, l)
	else:
		_record(l, PREEMPTED, now_ms)


## Sets the resume position to where playback is at `now_ms`.
func _set_position(l: _Line, now_ms: int) -> void:
	for s: Dictionary in l.segments:
		if now_ms < int(s["end_ms"]):
			l.pos_part = int(s["part"])
			var played: int = int((now_ms - int(s["start_ms"])) * int(s["rate"]) / 1000.0)
			l.pos_sample = int(s["from"]) + clampi(played, 0, int(s["samples"]))
			_forget_before(l)
			return
	# Past everything pushed (an underrun): continue with the next part.
	l.pos_part = l.pushed_part + 1
	l.pos_sample = 0
	_forget_before(l)


func _forget_before(l: _Line) -> void:
	for part: int in l.parts.keys():
		if part < l.pos_part:
			l.parts.erase(part)
	l.segments.clear()


func _drop(l: _Line, reason: String, now_ms: int) -> void:
	_queue.erase(l)
	_record(l, reason, now_ms)


func _record(l: _Line, reason: String, now_ms: int) -> void:
	l.parts.clear()
	dropped.append({"clip": l.clip, "line": l.line, "reason": reason, "at_ms": now_ms})
