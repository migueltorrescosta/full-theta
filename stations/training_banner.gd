class_name TrainingBanner
extends PanelContainer
## The Shakedown's step banner and Next button (FT-MIS-039, D235), shown on every station
## while a training run goes. The server says each station's step as a ship-computer line
## (content/dialogue/shakedown.json); the shell keeps the latest one per station in
## StationContext.training. The banner shows the focused station's step: the line's text
## with the player's current binding, its worked example, and Next. Next sends
## TrainingNextCommand; on a step that ends on a command it does nothing, and a player may
## press it anyway. Next has a key (the training_next intent), a pad chord and a tap.

const LINE_PREFIX: String = "shakedown."
const PAIR_PREFIX: String = "pair_"
## Station ids of the Shakedown: the six crew stations and the Captain seat.
const STATIONS: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "captain"
]

var ctx: StationContext
## The station whose step shows (the screen's focused station).
var station: String = ""

var _title: Label
var _text: Label
var _example: Label
var _next: Button


func setup(context: StationContext) -> void:
	ctx = context
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	custom_minimum_size = Vector2(420.0, 0.0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = "HeadingLabel"
	col.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	_example = Label.new()
	_example.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_example)
	_next = Button.new()
	_next.name = "Next"
	_next.custom_minimum_size = Vector2(0.0, 52.0)
	_next.pressed.connect(press)
	col.add_child(_next)
	visible = false


func _process(_delta: float) -> void:
	refresh()


## Shows the focused station's latest step, or hides.
func refresh() -> void:
	var entry: Dictionary = ctx.training.get(station, {})
	visible = not entry.is_empty()
	if not visible:
		return
	var device: String = ctx.matcher.device
	_title.text = tr("train.title")
	_text.text = BindingText.fill_markers(str(entry["text"]), ctx.settings.bindings, device)
	var key: String = str(entry.get("example", ""))
	_example.visible = key != ""
	if key != "":
		_example.text = BindingText.fill_markers(tr(key), ctx.settings.bindings, device)
	var done: bool = bool(entry.get("done", false))
	_next.visible = not done
	_next.text = "%s  (%s)" % [tr("train.next"), _next_binding(device)]


## Sends Next for the focused station (false when no step is showing).
func press() -> bool:
	if not visible or station == "":
		return false
	ctx.intents.command({"kind": "training_next", "station": station})
	return true


func _next_binding(device: String) -> String:
	return BindingText.describe_all(ctx.settings.bindings.bindings("training_next", device))


## Records a shakedown subtitle (a voice_line payload as SubtitleFeed keeps it) in
## `training`: station -> {"line", "text", "example", "done"}. The line id says whose it is
## (shakedown.<station>.<intent>, shakedown.pair_pN for a pair's two stations,
## shakedown.all_done for everyone). Other lines are ignored.
static func note(training: Dictionary, entry: Dictionary, pair_stations: Callable) -> void:
	var line: String = str(entry.get("line", ""))
	if not line.begins_with(LINE_PREFIX):
		return
	var rest: PackedStringArray = line.trim_prefix(LINE_PREFIX).split(".")
	var who: Array[String] = []
	var intent: String = ""
	var done: bool = false
	if rest.size() == 1 and rest[0] == "all_done":
		who.assign(STATIONS)
		done = true
	elif rest.size() == 1 and rest[0].begins_with(PAIR_PREFIX):
		who.assign(pair_stations.call(rest[0]))
		intent = rest[0]
	elif rest.size() == 2 and STATIONS.has(rest[0]):
		who.append(rest[0])
		intent = rest[1]
		done = intent == "track_done"
	for s: String in who:
		training[s] = {
			"line": line,
			"text": str(entry.get("text", "")),
			"example": "" if done else "train.ex." + intent,
			"done": done,
		}
