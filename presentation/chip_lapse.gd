class_name ChipLapse
extends RefCounted
## Remembers request chips nobody answered (C5): a chip that vanishes with almost no time
## left has lapsed, and the screen says so once, as a "Helm: Boost lapsed" note in its toast
## queue, so the requester's silence is not mistaken for a glitch. A chip that vanishes with
## time left was answered and leaves no note. The Captain's request list reads the same rule
## (ChipList).

## A chip gone with at most this many seconds left lapsed.
const LAPSE_TIME: float = 1.5

var _seen: Dictionary = {}


## Feeds the open chips ({id, text, left (seconds)}); returns the notes of the chips that
## lapsed since the last call, oldest first.
func update(chips: Array) -> Array[String]:
	var open: Dictionary = {}
	for c: Dictionary in chips:
		open[int(c["id"])] = true
	var out: Array[String] = []
	for id: int in _seen:
		if not open.has(id) and lapsed(float(_seen[id]["left"])):
			out.append(TranslationServer.translate("chip.lapsed") % _seen[id]["text"])
	_seen.clear()
	for c: Dictionary in chips:
		_seen[int(c["id"])] = {"text": str(c["text"]), "left": float(c["left"])}
	return out


## Whether a chip last seen with `time_left` seconds left, now gone, lapsed (else it was answered).
static func lapsed(time_left: float) -> bool:
	return time_left <= LAPSE_TIME


## What a chip does for whoever accepts it ("" when the chip has no effect text): the
## `chip.effect.<id>` string.
static func effect(chip_id: String) -> String:
	var key: String = "chip.effect." + chip_id
	var text: String = TranslationServer.translate(key)
	return "" if text == key else text
