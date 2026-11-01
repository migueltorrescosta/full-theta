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

## Distance from the top bar or the bottom edge, px.
const EDGE_GAP: float = 72.0
## The phone frame's view-top row under the top bar (selection chip, request chips), px.
const VIEW_TOP_ROW: float = 44.0

var ctx: StationContext
var kind: Kind = Kind.FORFEIT

var _floating: bool = true

var _title: Label
var _votes: Label
var _buttons: HBoxContainer


## `floating`: an overlay of the shell, placed clear of the view's centre; false for a
## prompt inside a screen's layout (the scoreboard's relaunch vote).
func setup(context: StationContext, prompt_kind: Kind, floating: bool = true) -> void:
	ctx = context
	kind = prompt_kind
	_floating = floating
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
	# Clear of the view's centre: the give-up vote under the top bar, the relaunch vote above
	# the bottom edge (over the scoreboard's rows or a friendly ship's main screen).
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()
	_place()


func _enter_tree() -> void:
	if _floating and not get_viewport().size_changed.is_connected(_place):
		get_viewport().size_changed.connect(_place)
		minimum_size_changed.connect(_place, CONNECT_DEFERRED)


## Where a floating prompt sits: clear of the view's centre, the give-up vote under the top
## bar, the relaunch vote above the bottom edge (over the scoreboard's rows or a friendly
## ship's main screen). On a phone (#28 follow-up, design 2.13) both float under the frame's
## view-top row, never near the gesture band.
func _place() -> void:
	if not _floating or not is_inside_tree():
		return
	var phone: bool = LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	var top: bool = kind == Kind.FORFEIT or phone
	if phone:
		# Back to the content's size (a wrapped title is taller before its first layout).
		reset_size()
	set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP if top else Control.PRESET_CENTER_BOTTOM
	)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
	if phone:
		position.y = phone_top(self)
	else:
		position.y += EDGE_GAP if top else -EDGE_GAP


## The top of a floating prompt on a phone, px in the parent: under the view-top row.
static func phone_top(node: Control) -> float:
	var top: float = main_top(node) + VIEW_TOP_ROW + UiTheme.TOUCH_GAP
	if node.get_parent() is Control:
		top -= (node.get_parent() as Control).get_global_rect().position.y
	return top


## Where a phone station's main area starts (its view-top row), viewport px: from the
## station screen beside `node` (the client shell's layer), else under the top bar.
static func main_top(node: Node) -> float:
	var parent: Node = node.get_parent()
	if parent != null:
		for n: Node in parent.find_children("*", "StationScreen", true, false):
			var s: StationScreen = n
			if s.is_visible_in_tree() and s.frame != null and s.frame.view_top.is_inside_tree():
				return s.frame.view_top.get_global_rect().position.y
	return SafeArea.margins(node).y + StationScreen.PHONE_BAR_HEIGHT


## Whether the prompt shows: a standing give-up vote on this ship in play outside a pause
## (PvP), or this session's eliminated ship may relaunch.
func wanted() -> bool:
	var crew: CrewState = ctx.crew
	if kind == Kind.RELAUNCH:
		# On the scoreboard its own prompt holds the vote, in its layout.
		return crew.can_relaunch() and crew.on_scoreboard() != _floating
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
	_place.call_deferred()


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
	b.custom_minimum_size = Vector2(140, UiTheme.TOUCH_PRIMARY)
	_buttons.add_child(b)
	return b


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
