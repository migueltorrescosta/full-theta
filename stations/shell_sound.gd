class_name ShellSound
extends Node
## The client's sound beyond voice and alert tones (#12, FT-AUD-016, FT-AUD-023,
## FT-AUD-024): effects for firing, explosions, docking, the jump drive, button presses and
## refused commands (GameSounds), and the ambient music (MusicPlayer) that plays while the
## run is on and ducks under voice lines and callouts. One per shell, not per kept station
## screen, so a hidden screen never doubles a sound. Which station hears an effect follows
## GameSounds.ROUTES for the stations of the screen showing (`stations_of`).
##
## The shell sets `voice_active` (a voice line is playing), `stations_of` and `music_dir`
## /`sounds_dir` through the two classes' static folders (app/).

## Refusal toasts that aren't refusals: no error sound.
const QUIET_TOASTS: Array[String] = ["toast.takeover", "toast.chip_answered", "toast.chip_declined"]

var ctx: StationContext
var sfx: GameSounds = GameSounds.new()
var music: MusicPlayer = MusicPlayer.new()
## Returns the station ids of the screen showing (Array); empty in the lobby.
var stations_of: Callable = Callable()
## Returns whether a voice line is playing.
var voice_playing: Callable = Callable()


func setup(context: StationContext) -> void:
	ctx = context
	add_child(sfx)
	add_child(music)
	ctx.crew.sim_event.connect(on_sim_event)
	ctx.crew.toast.connect(on_toast)


func _ready() -> void:
	# Every button added from now on taps; the menu's own buttons too.
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	music.volume = ctx.settings.music_volume
	music.voice_active = voice_playing.is_valid() and bool(voice_playing.call())
	music.set_playing(ctx.crew.is_started() and not ctx.crew.ship_outcome.has(ctx.crew.ship))


## A sim event: the effect its route names, when this screen hears it.
func on_sim_event(kind: StringName, p: Dictionary) -> void:
	var held: Array = stations_of.call() if stations_of.is_valid() else []
	var own: bool = int(p.get("ship", -1)) == ctx.crew.ship
	var clip: StringName = GameSounds.clip_for(kind, held, own)
	if clip != &"":
		sfx.play(clip, ctx.now_ms())


## A refusal toast sounds the error clip.
func on_toast(key: String, _args: Dictionary) -> void:
	if not QUIET_TOASTS.has(key):
		sfx.play(&"ui_error", ctx.now_ms())


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.is_connected("pressed", _on_pressed):
		(node as BaseButton).pressed.connect(_on_pressed)


func _on_pressed() -> void:
	sfx.play(&"ui_tap", ctx.now_ms())
