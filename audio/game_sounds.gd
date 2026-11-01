class_name GameSounds
extends Node
## Sound effects for the events that have no alert tone (FT-AUD-016, FT-AUD-023, #12): a
## weapon firing, a ship destroyed, docking and undocking, the jump drive spooling and
## arriving, a button pressed and a command refused. One CC0 clip per event
## (assets/sounds/sfx/, content/provenance.json), one player each on the `Sfx` bus, sent
## straight to Master so voice ducking never touches them (like the Alerts bus). The alert
## tones (AlertTones) stay for hits, faults, shield warnings, proximity and pings.
##
## `played` records the last PLAYED_KEPT clips that started (the spy seam for tests). The
## files live in assets/, which audio/ may not name (spec §2.2): app/ sets `sounds_dir`;
## while it is empty clips are recorded silently.

## A clip started: its name.
signal clip_played(clip: StringName)

const BUS: String = "Sfx"
const CLIPS: Array[StringName] = [
	&"fire",
	&"explosion",
	&"dock",
	&"undock",
	&"jump_charge",
	&"jump",
	&"ui_tap",
	&"ui_error",
]
## Sim event kind -> [stations that hear it ([] for every screen), clip, own ship only].
## Weapons hears its own ship's shots; everyone hears an explosion, the jump and the
## drive spooling; Helm hears the docking clamps (FT-SIM events, docs/protocol.md).
const ROUTES: Dictionary = {
	&"fired": [["weapons"], &"fire", true],
	&"destroyed": [[], &"explosion", false],
	&"docked": [["helm"], &"dock", true],
	&"undocked": [["helm"], &"undock", true],
	&"jump_spool": [[], &"jump_charge", true],
	&"jump_arrive": [[], &"jump", true],
}
## A clip repeated within this gap is skipped (ms): a salvo or a row of buttons must not
## drone. PROVISIONAL.
const GAP_MS: Dictionary = {&"fire": 150, &"ui_tap": 60, &"ui_error": 400, &"explosion": 300}
const PLAYED_KEPT: int = 32

## Folder of the `<clip>.ogg` files, set by app/.
static var sounds_dir: String = ""

## The last PLAYED_KEPT clip names that started, oldest first.
var played: Array[StringName] = []

var _players: Dictionary = {}
var _last_ms: Dictionary = {}


## Creates the Sfx bus when the layout lacks it (sent to Master, never to Voice or Music).
static func ensure_bus() -> void:
	SoundPlayers.ensure_bus(BUS)


## The clip a sim event makes for a screen holding `stations`, or &"" for none.
## `own` is whether the event is about the own ship.
static func clip_for(kind: StringName, stations: Array, own: bool) -> StringName:
	if not ROUTES.has(kind):
		return &""
	var route: Array = ROUTES[kind]
	if bool(route[2]) and not own:
		return &""
	var who: Array = route[0]
	if not who.is_empty():
		var hears: bool = false
		for s: Variant in stations:
			hears = hears or who.has(s)
		if not hears:
			return &""
	return route[1]


func _ready() -> void:
	ensure_bus()
	_players = SoundPlayers.add_players(self, CLIPS, BUS, sounds_dir, ".ogg")


## Plays `clip` unless it played within its GAP_MS; true when it started.
func play(clip: StringName, now_ms: int) -> bool:
	var player: AudioStreamPlayer = _players.get(clip)
	if player == null:
		return false
	if _last_ms.has(clip) and now_ms - int(_last_ms[clip]) < int(GAP_MS.get(clip, 0)):
		return false
	_last_ms[clip] = now_ms
	player.play()
	played.append(clip)
	if played.size() > PLAYED_KEPT:
		played.pop_front()
	clip_played.emit(clip)
	return true


## The player of a clip (tests check its bus and stream).
func player_of(clip: StringName) -> AudioStreamPlayer:
	return _players.get(clip)
