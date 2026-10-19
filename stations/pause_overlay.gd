class_name PauseOverlay
extends PanelContainer
## The pause (FT-NET-034, D96, D128): shown while a ship in play is paused, naming the
## uncovered stations. Crew of the paused ship get the abandon vote (cast or withdraw,
## with voters and votes needed); the host also gets Abandon (D127); the Captain and
## viewers of that ship may take over an uncovered station (FT-NET-042).

var ctx: StationContext

var _text: Label
var _votes: Label
var _buttons: HBoxContainer


func setup(context: StationContext) -> void:
	ctx = context
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 24)
	col.add_child(_text)
	_votes = Label.new()
	_votes.name = "Votes"
	col.add_child(_votes)
	_buttons = HBoxContainer.new()
	col.add_child(_buttons)
	ctx.crew.changed.connect(func(_what: StringName) -> void: refresh())
	refresh()


## The paused ship this client cares about: its own, else any.
func paused_ship() -> int:
	if ctx.crew.paused.has(ctx.crew.ship):
		return ctx.crew.ship
	return int(ctx.crew.paused.keys()[0]) if not ctx.crew.paused.is_empty() else -1


func refresh() -> void:
	var id: int = paused_ship()
	visible = id >= 0
	if not visible:
		return
	var p: Dictionary = ctx.crew.paused[id]
	var names: PackedStringArray = []
	for s: Variant in p.get("uncovered", []):
		names.append(tr("station." + str(s)))
	_text.text = tr("pause.waiting") % ", ".join(names)
	var v: Dictionary = ctx.crew.votes.get(id, {"voters": [], "needed": 0})
	var voters: Array = v.get("voters", [])
	_votes.text = tr("pause.votes") % [voters.size(), int(v.get("needed", 0)), ", ".join(voters)]
	_votes.visible = id == ctx.crew.ship
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if id != ctx.crew.ship:
		return
	if ctx.crew.is_crew():
		var voted: bool = _my_name() in voters
		_button("Vote", tr("pause.unvote") if voted else tr("pause.vote")).pressed.connect(
			func() -> void: ctx.intents.vote_abandon(id, not voted)
		)
	else:
		for s: Variant in p.get("uncovered", []):
			var st: String = str(s)
			_button("Takeover_" + st, tr("pause.take") % tr("station." + st)).pressed.connect(
				func() -> void: ctx.intents.takeover(id, st)
			)
	if ctx.crew.host:
		_button("Abandon", tr("pause.abandon")).pressed.connect(
			func() -> void: ctx.intents.abandon(id)
		)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	_buttons.add_child(b)
	return b


func _my_name() -> String:
	return ctx.client.name if ctx.client != null else ctx.settings.player_name
