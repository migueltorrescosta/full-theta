class_name VotePrompt
extends PanelContainer
## A crew vote outside the pause (#11), one prompt per kind:
## - FORFEIT (M4-Q10, D267 proposed, FT-MIS-016): in PvP, once a crewmate votes to give up,
##   the ship's crew see the vote with its voters and the votes needed, and cast or take
##   back theirs; the host gives up at once. In a pause the pause overlay holds the vote.
## - RELAUNCH (M4-Q2, D259 proposed): when this session's ship is out and its side may
##   relaunch, its crew vote for a fresh ship (lives left shown, unlimited or a count).

enum Kind { FORFEIT, RELAUNCH }

const KINDS: Array[StringName] = [
	&"votes",
	&"pause",
	&"picked",
	&"eliminated",
	&"relaunch",
	&"handover",
	&"session_over",
	&"fleet",
	&"abandoned",
	&"started",
]

var ctx: StationContext
var kind: Kind = Kind.FORFEIT

var _title: Label
var _votes: Label
var _buttons: HBoxContainer


func setup(context: StationContext, prompt_kind: Kind) -> void:
	ctx = context
	kind = prompt_kind
	name = "ForfeitPrompt" if kind == Kind.FORFEIT else "RelaunchPrompt"
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = "HeadingLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(320, 0)
	col.add_child(_title)
	_votes = Label.new()
	_votes.name = "Votes"
	_votes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_votes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_votes)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)
	col.add_child(_buttons)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


## Whether the prompt shows: a standing give-up vote on this ship in play outside a pause
## (PvP), or this session's eliminated ship may relaunch.
func wanted() -> bool:
	var crew: CrewState = ctx.crew
	if kind == Kind.RELAUNCH:
		return crew.can_relaunch()
	var v: Array = crew.votes.get(crew.ship, {}).get("voters", [])
	return (
		crew.is_pvp()
		and not v.is_empty()
		and not crew.paused.has(crew.ship)
		and not crew.eliminated.has(crew.ship)
		and crew.session_over.is_empty()
		and crew.ship == crew.home_ship()
	)


func refresh() -> void:
	visible = wanted()
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if not visible:
		return
	if kind == Kind.RELAUNCH:
		_refresh_relaunch()
	else:
		_refresh_forfeit()


func _refresh_forfeit() -> void:
	var crew: CrewState = ctx.crew
	var id: int = crew.ship
	var v: Dictionary = crew.votes.get(id, {})
	var voters: Array = v.get("voters", [])
	_title.text = tr("forfeit.title") % crew.ship_name(id)
	_votes.text = tr("forfeit.votes") % [voters.size(), int(v.get("needed", 0)), ", ".join(voters)]
	if crew.is_crew():
		var voted: bool = crew.has_abandon_vote()
		_button("Vote", tr("forfeit.unvote") if voted else tr("forfeit.vote")).pressed.connect(
			func() -> void: ctx.intents.vote_abandon(id, not voted)
		)
	if crew.host:
		_button("GiveUp", tr("forfeit.now"), "RailDangerButton").pressed.connect(
			func() -> void: ctx.intents.abandon(id)
		)


func _refresh_relaunch() -> void:
	var crew: CrewState = ctx.crew
	var id: int = crew.home_ship()
	var lives: int = crew.lives_left()
	_title.text = (
		tr("relaunch.title")
		% [
			crew.ship_name(id),
			tr("relaunch.unlimited") if lives < 0 else tr("relaunch.lives") % lives,
		]
	)
	var v: Dictionary = crew.relaunch_votes.get(id, {})
	var voters: Array = v.get("voters", [])
	_votes.text = tr("relaunch.votes") % [voters.size(), int(v.get("needed", 0)), ", ".join(voters)]
	_votes.visible = not voters.is_empty()
	var me: String = ctx.settings.player_name if ctx.settings != null else ""
	var voted: bool = crew.has_relaunch_vote(me)
	_button("Relaunch", tr("relaunch.unvote") if voted else tr("relaunch.vote")).pressed.connect(
		func() -> void: ctx.intents.vote_relaunch(id, not voted)
	)


func _button(node_name: String, text: String, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(140, 48)
	_buttons.add_child(b)
	return b


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
