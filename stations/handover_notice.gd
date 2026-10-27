class_name HandoverNotice
extends PanelContainer
## The viewer handover notice (#11; FT-MIS-030, D79, D91): when this session's ship is out
## and the server moved it to a surviving friendly ship's main screen, a short notice says
## which ship is out, why, and which ship the player now watches. OK hides it; a later
## handover or a relaunch replaces it. A handover to the scoreboard shows the scoreboard
## instead (ScoreboardScreen).

const KINDS: Array[StringName] = [&"handover", &"eliminated", &"relaunch", &"picked"]

var ctx: StationContext

var _text: Label
var _ok: Button
## The handover the player dismissed, so a refresh doesn't bring it back.
var _seen: Dictionary = {}


func setup(context: StationContext) -> void:
	ctx = context
	name = "HandoverNotice"
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_text = Label.new()
	_text.name = "Text"
	_text.theme_type_variation = "HeadingLabel"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(320, 0)
	col.add_child(_text)
	_ok = Button.new()
	_ok.name = "Ok"
	_ok.custom_minimum_size = Vector2(160, 48)
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok.pressed.connect(dismiss)
	col.add_child(_ok)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


## "Kestrel is out: destroyed. You're watching Heron now."
func notice_text() -> String:
	var h: Dictionary = ctx.crew.handover
	var out: int = int(h.get("ship", -1))
	var reason: String = str(ctx.crew.eliminated.get(out, {}).get("reason", "destroyed"))
	return (
		tr("handover.text")
		% [ctx.crew.ship_name(out), tr("out." + reason), ctx.crew.ship_name(int(h["to_ship"]))]
	)


func refresh() -> void:
	var h: Dictionary = ctx.crew.handover
	visible = (
		not h.is_empty() and int(h.get("to_ship", -1)) != FleetMessages.TO_SCOREBOARD and h != _seen
	)
	if visible:
		_text.text = notice_text()
		_ok.text = tr("handover.ok")


func dismiss() -> void:
	_seen = ctx.crew.handover
	visible = false


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
