class_name ChipLapse
extends RefCounted
## Remembers request chips nobody answered (C5): a chip that vanishes with almost no time
## left has lapsed, and its row stays a few seconds as a "Helm: Boost lapsed" note in the
## chip's own place, so the requester's silence is not mistaken for a glitch. A chip that
## vanishes with time left was answered and leaves no note.

## How long a lapsed note stays (ms).
const SHOW_MS: int = 4000
## A chip gone with at most this many seconds left lapsed.
const LAPSE_S: float = 1.5

var _seen: Dictionary = {}
var _notes: Array[Dictionary] = []


## Feeds the open chips ({id, text, left (seconds)}) at `now_ms`; returns the lapsed notes
## still to show, oldest first.
func update(chips: Array, now_ms: int) -> Array[String]:
	var open: Dictionary = {}
	for c: Dictionary in chips:
		open[int(c["id"])] = true
	for id: int in _seen:
		if not open.has(id) and float(_seen[id]["left"]) <= LAPSE_S:
			_notes.append({"text": _seen[id]["text"], "until": now_ms + SHOW_MS})
	_seen.clear()
	for c: Dictionary in chips:
		_seen[int(c["id"])] = {"text": str(c["text"]), "left": float(c["left"])}
	_notes = _notes.filter(func(n: Dictionary) -> bool: return int(n["until"]) > now_ms)
	var out: Array[String] = []
	for n: Dictionary in _notes:
		out.append(TranslationServer.translate("chip.lapsed") % n["text"])
	return out


## What a chip does for whoever accepts it ("" when the chip has no effect text): the
## `chip.effect.<id>` string.
static func effect(chip_id: String) -> String:
	var key: String = "chip.effect." + chip_id
	var text: String = TranslationServer.translate(key)
	return "" if text == key else text
