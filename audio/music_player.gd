class_name MusicPlayer
extends Node
## Low ambient music while a run is on (owner M5-Q4, D312, FT-AUD-024): CC0 tracks
## (assets/music/, content/provenance.json) play one after the other on the `Music` bus,
## sent to Master. The bus ducks under voice: while a voice line or callout plays
## (`voice_active`) the music falls by DUCK_DB over ATTACK_TIME, and rises back over
## RELEASE_TIME once the voice has been quiet for HOLD_TIME, so the gaps between callouts don't
## pump. A scripted volume (not a sidechain compressor), so it behaves the same in the
## browser and can be tested without audio output: `bus_db()` is a pure function of
## the player's own state and `advance()` moves it.
##
## The player's own volume is the Music setting (ClientSettings.music_volume, 0..1,
## linear), set in `volume`. The tracks live in assets/, which audio/ may not name (spec
## §2.2): app/ sets `music_dir`; while it is empty nothing plays.

const BUS: String = "Music"
const TRACKS: Array[String] = ["deep_space_array", "the_magnificent_cosmos", "observing_the_star"]
## The music's level at volume 1.0 (dB): it sits under the effects and voice.
const FULL_DB: float = -6.0
## How far a voice line pulls the music down (dB), how fast down and up (s), and how long
## the voice must be quiet before the music rises (s). PROVISIONAL.
const DUCK_DB: float = -14.0
const ATTACK_TIME: float = 0.2
const RELEASE_TIME: float = 1.2
const HOLD_TIME: float = 0.6
## Below this volume the bus is muted rather than set to a very low dB.
const SILENT_DB: float = -80.0

## Folder of the `<track>.ogg` files, set by app/.
static var music_dir: String = ""

## The Music setting, 0..1 linear.
var volume: float = 0.5
## Whether a voice line or callout is playing; the owner sets it every frame.
var voice_active: bool = false
## 0 (full) .. 1 (fully ducked).
var duck: float = 0.0

var _quiet_time: float = 0.0
var _player: AudioStreamPlayer
var _index: int = 0
var _on: bool = false


## Creates the Music bus when the layout lacks it (sent to Master).
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, "Master")


## The bus level (dB) for the volume setting and the duck amount; SILENT_DB at volume 0.
static func level_db(vol: float, duck_amount: float) -> float:
	if vol <= 0.0:
		return SILENT_DB
	return linear_to_db(clampf(vol, 0.0, 1.0)) + FULL_DB + DUCK_DB * clampf(duck_amount, 0.0, 1.0)


func _ready() -> void:
	ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "Track"
	_player.bus = BUS
	_player.finished.connect(_next)
	add_child(_player)
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## Moves the duck by `delta` seconds toward its target and sets the bus level.
func advance(delta: float) -> void:
	if voice_active:
		_quiet_time = 0.0
		duck = minf(1.0, duck + delta / ATTACK_TIME)
	else:
		_quiet_time += delta
		if _quiet_time >= HOLD_TIME:
			duck = maxf(0.0, duck - delta / RELEASE_TIME)
	_apply()


## The current bus level (dB).
func bus_db() -> float:
	return level_db(volume, duck)


## Starts or stops the music. It resumes with the track it stopped on.
func set_playing(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if _player == null:
		return
	if on:
		_start_track()
	else:
		_player.stop()


## The name of the track selected, "" outside the list.
func current_track() -> String:
	return TRACKS[_index % TRACKS.size()]


func is_playing() -> bool:
	return _on


func _next() -> void:
	_index = (_index + 1) % TRACKS.size()
	if _on:
		_start_track()


func _start_track() -> void:
	if music_dir == "":
		return
	var stream: AudioStream = load(music_dir.path_join(current_track() + ".ogg")) as AudioStream
	if stream == null:
		return
	_player.stream = stream
	_player.play()


func _apply() -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, bus_db())
	AudioServer.set_bus_mute(index, volume <= 0.0)
