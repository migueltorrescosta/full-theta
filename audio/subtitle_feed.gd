class_name SubtitleFeed
extends RefCounted
## Subtitles of voice lines: every voice_line event becomes a subtitle at once, whether
## or not its audio is ever heard (audio false, missing local clip, expired, coalesced,
## preempted) (FT-AUD-010). Pure; the time is passed in. The station UI (#7) renders
## entries, labelling each with the UI string `label_key` (subtitle.computer, subtitle.npc).

## PROVISIONAL: on-screen time is MIN_MS plus PER_CHAR_MS per character, capped at MAX_MS.
const MIN_MS: int = 2000
const PER_CHAR_MS: int = 60
const MAX_MS: int = 10000
## PROVISIONAL: at most this many subtitles are kept; the oldest go first.
const KEEP: int = 6

var _entries: Array[Dictionary] = []


static func duration_ms(text: String) -> int:
	return mini(MIN_MS + PER_CHAR_MS * text.length(), MAX_MS)


## Adds the subtitle of a voice_line payload and returns it: {"clip", "line", "text",
## "role", "label_key", "shown_ms", "expires_ms"}.
func add(payload: Dictionary, now_ms: int) -> Dictionary:
	var text: String = str(payload.get("text", ""))
	var role: String = str(payload.get("role", "npc"))
	var entry: Dictionary = {
		"clip": int(payload.get("clip", -1)),
		"line": str(payload.get("line", "")),
		"text": text,
		"role": role,
		"label_key": "subtitle." + role,
		"shown_ms": now_ms,
		"expires_ms": now_ms + duration_ms(text),
	}
	_entries.append(entry)
	while _entries.size() > KEEP:
		_entries.pop_front()
	return entry


## Subtitles still showing at `now_ms`, oldest first; expired ones are forgotten.
func active(now_ms: int) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if now_ms < int(e["expires_ms"]):
			kept.append(e)
	_entries = kept
	return kept.duplicate()
