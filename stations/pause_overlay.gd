class_name PauseOverlay
extends PanelContainer
## The pause (FT-NET-034, D96, D128): shown while a ship in play is paused, naming the
## uncovered stations. Crew of the paused ship get the abandon vote (cast or withdraw,
## with voters and votes needed); the host also gets Abandon (D127); the Captain and
## viewers of that ship may take over an uncovered station (FT-NET-042).
##
## Multi-ship sessions (#11, M4-Q8, D265 proposed): players of an allied ship may take over a
## paused ship's uncovered station too ("Take Science on Heron"); there is no accept prompt,
## the first claim wins, and the server refuses a takeover that would leave the taker's own
## ship uncovered. An enemy ship's pause offers nothing. In PvP the vote is the give-up
## (forfeit) vote (M4-Q10).

## The crew changes the overlay depends on.
const KINDS: Array[StringName] = [&"pause", &"votes", &"picked", &"catalogue", &"fleet"]

var ctx: StationContext

var _text: Label
var _votes: Label
var _buttons: HFlowContainer


func setup(context: StationContext) -> void:
	ctx = context
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_text = Label.new()
	_text.theme_type_variation = "HeadingLabel"
	col.add_child(_text)
	_votes = Label.new()
	_votes.name = "Votes"
	col.add_child(_votes)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 8)
	_buttons.add_theme_constant_override("v_separation", 8)
	col.add_child(_buttons)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


## The paused ship this client cares about: its own, else an allied one, else any.
func paused_ship() -> int:
	if ctx.crew.paused.has(ctx.crew.ship):
		return ctx.crew.ship
	for id: Variant in ctx.crew.paused:
		if ctx.crew.allied(int(id), ctx.crew.ship):
			return int(id)
	return int(ctx.crew.paused.keys()[0]) if not ctx.crew.paused.is_empty() else -1


## Whether this client may offer to take over a station on the paused `id` (M4-Q8): its own
## ship's Captain and viewers, or any player of an allied ship; never an enemy.
func may_take_over(id: int) -> bool:
	if id == ctx.crew.ship:
		return not ctx.crew.is_crew()
	return ctx.crew.entry != "" and ctx.crew.allied(id, ctx.crew.ship)


func refresh() -> void:
	var id: int = paused_ship()
	visible = id >= 0 or ctx.crew.host_paused
	if not visible:
		return
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if id < 0:
		# A host pause alone (FT-MIS-040): no uncovered list, no abandon.
		_text.text = tr("pause.host")
		_votes.visible = false
		_resume_button()
		return
	var p: Dictionary = ctx.crew.paused[id]
	var names: PackedStringArray = []
	for s: Variant in p.get("uncovered", []):
		names.append(tr("station." + str(s)))
	var own: bool = id == ctx.crew.ship
	if own:
		_text.text = tr("pause.waiting") % ", ".join(names)
	else:
		_text.text = tr("pause.waiting_ship") % [ctx.crew.ship_name(id), ", ".join(names)]
	var pvp: bool = ctx.crew.is_pvp()
	var v: Dictionary = ctx.crew.votes.get(id, {"voters": [], "needed": 0})
	var voters: Array = v.get("voters", [])
	_votes.text = (
		tr("pause.forfeit_votes" if pvp else "pause.votes")
		% [voters.size(), int(v.get("needed", 0)), ", ".join(voters)]
	)
	_votes.visible = own
	if own and ctx.crew.is_crew():
		var voted: bool = ctx.crew.session in v.get("sessions", [])
		var key: String = "pause.%s%s" % ["un" if voted else "", "forfeit" if pvp else "vote"]
		_button("Vote", tr(key)).pressed.connect(
			func() -> void: ctx.intents.vote_abandon(id, not voted)
		)
	elif may_take_over(id):
		for s: Variant in p.get("uncovered", []):
			var st: String = str(s)
			var text: String = tr("pause.take") % tr("station." + st)
			if not own:
				text = tr("pause.take_on") % [tr("station." + st), ctx.crew.ship_name(id)]
			_button("Takeover_" + st, text).pressed.connect(
				func() -> void: ctx.intents.takeover(id, st)
			)
	if own and ctx.crew.host:
		_button("Abandon", tr("pause.forfeit_now" if pvp else "pause.abandon")).pressed.connect(
			func() -> void: ctx.intents.abandon(id)
		)
	_resume_button()


## Resume, on the host's client during a host pause (also over a coverage pause).
func _resume_button() -> void:
	if ctx.crew.host_paused and ctx.crew.host:
		_button("Resume", tr("pause.resume")).pressed.connect(
			func() -> void: ctx.intents.host_pause(false)
		)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	_buttons.add_child(b)
	return b


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
