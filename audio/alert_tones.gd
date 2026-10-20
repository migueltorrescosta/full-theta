class_name AlertTones
extends Node
## Alert tones (FT-AUD-009, T056): short CC0 tones on their own `Alerts` bus, sent
## straight to Master, so voice ducking, fades or a queue on the Voice buses never block
## them. One player per tone, so a ping chime never cuts a hit thump. Tones complement the
## ship computer's spoken lines, they don't repeat words. The files are synthesised by
## tools/make_alert_tones.py (assets/sounds/alerts/, content/provenance.json).
##
## `played` records the last PLAYED_KEPT tones that started (the spy seam for scene
## tests; capped, so a long session doesn't grow it).
##
## The tone files live in assets/, which audio/ may not name (spec §2.2): app/ sets
## `sounds_dir` (MainMenu, ALERT_SOUNDS); while it is empty tones are recorded silently.

## A tone started: its name.
signal tone_played(tone: StringName)

const BUS: String = "Alerts"
const TONES: Array[StringName] = [
	&"hit",
	&"fault",
	&"shield_low",
	&"proximity",
	&"ping",
	&"alert_red",
	&"alert_yellow",
	&"alert_normal",
]
## A tone repeated within this gap is skipped (ms), so a burst of hits or the sim's
## repeating proximity warning doesn't drone. PROVISIONAL.
const GAP_MS: Dictionary = {&"hit": 200, &"proximity": 2000}
const PLAYED_KEPT: int = 32

## Folder of the `<tone>.wav` files, set by app/.
static var sounds_dir: String = ""

## The last PLAYED_KEPT tone names that started, oldest first.
var played: Array[StringName] = []

var _players: Dictionary = {}
var _last_ms: Dictionary = {}


## Creates the Alerts bus when the layout lacks it (sent to Master, never to Voice).
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, "Master")


func _ready() -> void:
	ensure_bus()
	for t: StringName in TONES:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = String(t)
		p.bus = BUS
		if sounds_dir != "":
			p.stream = load(sounds_dir.path_join(String(t) + ".wav")) as AudioStream
		add_child(p)
		_players[t] = p


## Plays `tone` unless it played within its GAP_MS; true when it started.
func play(tone: StringName, now_ms: int) -> bool:
	var player: AudioStreamPlayer = _players.get(tone)
	if player == null:
		return false
	if _last_ms.has(tone) and now_ms - int(_last_ms[tone]) < int(GAP_MS.get(tone, 0)):
		return false
	_last_ms[tone] = now_ms
	player.play()
	played.append(tone)
	if played.size() > PLAYED_KEPT:
		played.pop_front()
	tone_played.emit(tone)
	return true


## The player of a tone (tests check its bus and stream).
func player_of(tone: StringName) -> AudioStreamPlayer:
	return _players.get(tone)
