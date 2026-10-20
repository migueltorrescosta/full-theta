class_name OutcomeCard
extends PanelContainer
## The outcome card (FT-M1-012, D178): on every station of a ship whose run ended, Victory
## or Ship lost with the run time and hull left. Crew cast or withdraw a "Run again" vote
## (voters and votes needed shown, like the abandon vote); the host runs it again at
## once. The card goes when the server resets the run (CrewState.reset_run).

## The crew changes the card depends on.
const KINDS: Array[StringName] = [&"run_over", &"reset", &"picked", &"catalogue"]

var ctx: StationContext

var _title: Label
var _stats: Label
var _votes: Label
var _buttons: HBoxContainer


func setup(context: StationContext) -> void:
	ctx = context
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_stats = Label.new()
	_stats.name = "Stats"
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stats)
	_votes = Label.new()
	_votes.name = "Votes"
	col.add_child(_votes)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_buttons)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


func refresh() -> void:
	var card: Dictionary = ctx.crew.run_over.get(ctx.crew.ship, {})
	visible = not card.is_empty() and ctx.crew.entry != ""
	if not visible:
		return
	_title.text = tr("outcome.win" if card.get("outcome", "") == "win" else "outcome.loss")
	var secs: int = int(card.get("time_s", 0.0))
	var hull: int = roundi(float(card.get("hull", 0.0)) * 100.0)
	_stats.text = tr("outcome.stats") % ["%d:%02d" % [secs / 60, secs % 60], hull]
	var voters: Array = card.get("voters", [])
	_votes.text = (
		tr("outcome.votes") % [voters.size(), int(card.get("needed", 0)), ", ".join(voters)]
	)
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var ship: int = ctx.crew.ship
	if ctx.crew.host:
		_button("RunAgain", tr("outcome.restart")).pressed.connect(
			func() -> void: ctx.intents.run_again(ship, true)
		)
	elif ctx.crew.is_crew():
		var voted: bool = ctx.crew.session in card.get("sessions", [])
		_button("Vote", tr("outcome.unvote") if voted else tr("outcome.vote")).pressed.connect(
			func() -> void: ctx.intents.run_again(ship, not voted)
		)


func _button(node_name: String, text: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	_buttons.add_child(b)
	return b


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
