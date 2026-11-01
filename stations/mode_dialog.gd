class_name ModeDialog
extends AcceptDialog
## The host's mode dialog in the lobby (#11; M4-Q6, FT-MIS-031, FT-GEN-002): a button per
## session mode (co-op, the three PvP types and holdout), the mode's one-line description,
## and in TEAMS the win rule. Each choice goes to the server (SessionMode); the dialog shows
## what the `fleet` event says. Read-only for the others and once the universe has started.

## The session modes and team win rules, in SessionRules order (the wire names).
const MODES: Array[String] = ["coop", "race", "last_standing", "teams", "holdout"]
const TEAM_WINS: Array[String] = ["last_team_standing", "first_to_finish"]
const GAP: int = UiTheme.TOUCH_GAP

var ctx: StationContext

var _grid: GridContainer
var _desc: Label
var _team_win: HBoxContainer


func setup(context: StationContext) -> void:
	ctx = context
	name = "ModeDialog"
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", GAP)
	add_child(col)
	_grid = GridContainer.new()
	_grid.name = "Modes"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	col.add_child(_grid)
	for mode: String in MODES:
		_grid.add_child(_button("Mode_" + mode, choose.bind(mode, "")))
	_desc = Label.new()
	_desc.name = "ModeDesc"
	_desc.theme_type_variation = "DimLabel"
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.x = 300.0
	col.add_child(_desc)
	_team_win = HBoxContainer.new()
	_team_win.name = "TeamWin"
	_team_win.add_theme_constant_override("separation", GAP)
	col.add_child(_team_win)
	for rule: String in TEAM_WINS:
		_team_win.add_child(_button("Win_" + rule, _choose_team_win.bind(rule)))
	refresh()


## Whether the host may change the mode: only before the universe starts.
func editable() -> bool:
	return ctx.crew.host and not bool(ctx.crew.fleet.get("started", false))


## The host's choice of mode and team win rule; holdout lives stay the mode's default (-1).
func choose(mode: String, team_win: String = "") -> void:
	if editable():
		var rule: String = (
			team_win if team_win != "" else str(ctx.crew.fleet.get("team_win", TEAM_WINS[0]))
		)
		ctx.intents.set_mode(mode, rule, -1)
	refresh()


## Shows the session's mode and whether the host may still change it.
func refresh() -> void:
	var can: bool = editable()
	var mode: String = ctx.crew.mode()
	title = tr("lobby.mode_title")
	ok_button_text = tr("lobby.done")
	for b: Node in _grid.get_children():
		var id: String = str(b.name).trim_prefix("Mode_")
		(b as Button).text = tr("mode." + id)
		(b as Button).set_pressed_no_signal(id == mode)
		(b as Button).disabled = not can
	var desc: String = tr("mode.%s.desc" % mode)
	if mode == "holdout":
		desc = desc % maxi(int(ctx.crew.fleet.get("lives", 3)), 0)
	if not ctx.crew.host:
		desc += " " + tr("lobby.mode_host_only")
	_desc.text = desc
	_team_win.visible = mode == "teams"
	for b: Node in _team_win.get_children():
		var rule: String = str(b.name).trim_prefix("Win_")
		(b as Button).text = tr("mode.win." + rule)
		(b as Button).set_pressed_no_signal(rule == str(ctx.crew.fleet.get("team_win", "")))
		(b as Button).disabled = not can


## Opens it sized for the window: two columns on a narrow one.
func open(narrow: bool) -> void:
	_grid.columns = 2 if narrow else 3
	# An autowrapped label needs a width, or the dialog grows tall.
	_desc.custom_minimum_size.x = 300.0 if narrow else 480.0
	refresh()
	reset_size()
	popup_centered_clamped(Vector2i(560, 0), 0.9)


func _choose_team_win(rule: String) -> void:
	choose(ctx.crew.mode(), rule)


func _button(node_name: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	return b
