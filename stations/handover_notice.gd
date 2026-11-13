class_name HandoverNotice
extends PanelContainer
## The viewer handover notice (#11; FT-MIS-030, D79, D91): when this session's ship is out
## and the server moved it to a surviving friendly ship's main screen, a short notice says
## which ship is out, why, and which ship the player now watches. It hides by itself after
## SHOW_TIME and lets every click through, so it never covers the HUD for long (R24-18); the
## top bar names the watched ship. A later handover or a relaunch replaces it. A handover
## to the scoreboard shows the scoreboard instead (ScoreboardScreen).
##
## A handover shows once: `seen` outlives the screen, so the shell rebuilt after a reconnect
## (the server sends the handover again) doesn't show it a second time.
##
## On a phone (#28 follow-up, design 2.13) the notice sits under the frame's view-top row
## (VotePrompt.phone_top).

const KINDS: Array[StringName] = [&"handover", &"eliminated", &"relaunch", &"picked"]
## How long the notice shows (s).
const SHOW_TIME: float = 6.0

## The handovers already shown, as seen_key strings, for this run of the game.
static var seen: Dictionary = {}

var ctx: StationContext

var _text: Label
## Seconds the notice still shows.
var _left: float = 0.0


func setup(context: StationContext) -> void:
	ctx = context
	name = "HandoverNotice"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = Label.new()
	_text.name = "Text"
	_text.theme_type_variation = "HeadingLabel"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(320, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	ctx.crew.changed.connect(_on_crew_changed)
	visible = false
	refresh()
	_place()


func _enter_tree() -> void:
	PhoneSheet.follow_viewport(self, _place, true)
	_place.call_deferred()


## On a phone: centred under the view-top row; elsewhere where the shell put it.
func _place() -> void:
	if not is_inside_tree() or _text == null:
		return
	if PhoneSheet.is_phone(self):
		reset_size()
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		position.y = VotePrompt.phone_top(self)


## "Kestrel is out: destroyed. You're watching Heron now."
func notice_text() -> String:
	var h: Dictionary = ctx.crew.handover
	var out: int = int(h.get("ship", -1))
	var reason: String = str(ctx.crew.eliminated.get(out, {}).get("reason", "destroyed"))
	return (
		tr("handover.text")
		% [ctx.crew.ship_name(out), tr("out." + reason), ctx.crew.ship_name(int(h["to_ship"]))]
	)


## What identifies a handover across a rebuilt shell: the seat's rejoin token (one per
## joined game) and the handover itself.
func seen_key() -> String:
	var token: String = ctx.client.token if ctx.client != null else ""
	return "%s|%s" % [token, var_to_str(ctx.crew.handover)]


## Shows a handover to a friendly ship not shown before; a handover to the scoreboard, or
## none, hides the notice.
func refresh() -> void:
	var h: Dictionary = ctx.crew.handover
	if h.is_empty() or int(h.get("to_ship", -1)) == FleetMessages.TO_SCOREBOARD:
		dismiss()
		return
	if seen.has(seen_key()):
		if visible:
			_text.text = notice_text()
		return
	seen[seen_key()] = true
	_text.text = notice_text()
	_left = SHOW_TIME
	visible = true
	_place.call_deferred()


func dismiss() -> void:
	_left = 0.0
	visible = false


func _process(delta: float) -> void:
	tick(delta)


## Counts the notice down by `delta` seconds; it hides at zero.
func tick(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		dismiss()


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
