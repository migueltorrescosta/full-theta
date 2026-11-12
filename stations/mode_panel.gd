class_name ModePanel
extends VBoxContainer
## The mode part of the host's Game setup sheet (#11; M4-Q6, FT-MIS-031, FT-GEN-002; #37 C1):
## a button per session mode (co-op, the three PvP types and holdout), the mode's one-line
## description, and in TEAMS the win rule. Each choice goes to the server (GameMode); the panel
## shows what the `fleet` event says. Only the host opens the sheet; the buttons grey once the
## universe has started. Under the mode, the host's two options as switches (#40 D1, D2:
## "Pause when someone drops", "Fill light stations with bots"), and the run modifier with its
## detail and a Reroll button while there is another to roll (gp-11); no row without one.

## The session modes and team win rules, in GameRules order (the wire names).
const MODES: Array[String] = ["coop", "race", "last_standing", "teams", "holdout"]
const TEAM_WINS: Array[String] = ["last_team_standing", "first_to_finish"]
const GAP: int = UiTheme.TOUCH_GAP
## The run modifier definitions the client names (RunModifierDef, by id): loaded once from
## MODIFIER_DIR; tests may set them.
const MODIFIER_DIR: String = "res://content/runs/modifiers"

static var modifier_defs: Dictionary = {}
static var _modifiers_loaded: bool = false

var ctx: StationContext

var _grid: GridContainer
var _desc: Label
var _team_win: HBoxContainer
var _drop_pause: CheckButton
var _fill_bots: CheckButton
var _modifier: HBoxContainer
var _modifier_name: Label
var _modifier_detail: Label
var _reroll: Button


func setup(context: StationContext) -> void:
	ctx = context
	name = "ModePanel"
	add_theme_constant_override("separation", GAP)
	_grid = GridContainer.new()
	_grid.name = "Modes"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	add_child(_grid)
	for mode: String in MODES:
		_grid.add_child(_button("Mode_" + mode, choose.bind(mode, "")))
	_desc = Label.new()
	_desc.name = "ModeDesc"
	_desc.theme_type_variation = "DimLabel"
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.x = 260.0
	add_child(_desc)
	_team_win = HBoxContainer.new()
	_team_win.name = "TeamWin"
	_team_win.add_theme_constant_override("separation", GAP)
	add_child(_team_win)
	for rule: String in TEAM_WINS:
		_team_win.add_child(_button("Win_" + rule, _choose_team_win.bind(rule)))
	_drop_pause = _switch("DropPause", "drop_pause")
	_fill_bots = _switch("FillBots", "fill_bots")
	_modifier = HBoxContainer.new()
	_modifier.name = "Modifier"
	_modifier.add_theme_constant_override("separation", GAP)
	add_child(_modifier)
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	_modifier.add_child(words)
	_modifier_name = Label.new()
	_modifier_name.name = "ModifierName"
	words.add_child(_modifier_name)
	_modifier_detail = Label.new()
	_modifier_detail.name = "ModifierDetail"
	_modifier_detail.theme_type_variation = "DimLabel"
	_modifier_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_modifier_detail)
	_reroll = Button.new()
	_reroll.name = "Reroll"
	_reroll.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_reroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reroll.pressed.connect(func() -> void: ctx.intents.reroll_modifier())
	_modifier.add_child(_reroll)
	refresh()


## The run modifier definition of `id`, or null (none, or one this client doesn't have).
static func modifier_def(id: String) -> RunModifierDef:
	if not _modifiers_loaded:
		_modifiers_loaded = true
		if DirAccess.dir_exists_absolute(MODIFIER_DIR):
			for path: String in DefLibrary.list_tres(MODIFIER_DIR):
				var def: RunModifierDef = load(path) as RunModifierDef
				if def != null and not modifier_defs.has(String(def.id)):
					modifier_defs[String(def.id)] = def
	return modifier_defs.get(id) as RunModifierDef


## Whether the host may change the mode: only before the universe starts.
func editable() -> bool:
	return ctx.crew.host and not bool(ctx.crew.fleet.get("started", false))


## The host's choice of mode and team win rule; holdout lives stay the mode's default (-1).
func choose(mode: String, team_win: String = "") -> void:
	if editable():
		var rule: String = (
			team_win if team_win != "" else str(ctx.crew.fleet.get("team_win", TEAM_WINS[0]))
		)
		ctx.intents.set_mode(mode, rule, -1, option("drop_pause"), option("fill_bots"))
	refresh()


## A host option as the `fleet` event says it (off until it does).
func option(id: String) -> bool:
	return bool(ctx.crew.fleet.get(id, false))


## The host flips an option: the mode, its rule and holdout lives stay as they are.
func set_option(id: String, on: bool) -> void:
	if editable():
		var lives: int = (
			int(ctx.crew.fleet.get("lives", -1)) if ctx.crew.mode() == "holdout" else -1
		)
		var pause: bool = on if id == "drop_pause" else option("drop_pause")
		var fill: bool = on if id == "fill_bots" else option("fill_bots")
		var rule: String = str(ctx.crew.fleet.get("team_win", TEAM_WINS[0]))
		ctx.intents.set_mode(ctx.crew.mode(), rule, lives, pause, fill)
	refresh()


## Shows the game's mode and whether the host may still change it.
func refresh() -> void:
	var can: bool = editable()
	var mode: String = ctx.crew.mode()
	for b: Node in _grid.get_children():
		var id: String = str(b.name).trim_prefix("Mode_")
		(b as Button).text = tr("mode." + id)
		(b as Button).set_pressed_no_signal(id == mode)
		(b as Button).disabled = not can
	var desc: String = tr("mode.%s.desc" % mode)
	if mode == "holdout":
		desc = desc % maxi(int(ctx.crew.fleet.get("lives", 3)), 0)
	_desc.text = desc
	_team_win.visible = mode == "teams"
	for b: Node in _team_win.get_children():
		var rule: String = str(b.name).trim_prefix("Win_")
		(b as Button).text = tr("mode.win." + rule)
		(b as Button).set_pressed_no_signal(rule == str(ctx.crew.fleet.get("team_win", "")))
		(b as Button).disabled = not can
	for pair: Array in [[_drop_pause, "drop_pause"], [_fill_bots, "fill_bots"]]:
		var sw: CheckButton = pair[0]
		sw.text = tr("lobby.option." + str(pair[1]))
		sw.set_pressed_no_signal(option(pair[1]))
		sw.disabled = not can
	var def: RunModifierDef = modifier_def(str(ctx.crew.fleet.get("modifier", "")))
	_modifier.visible = def != null
	if def != null:
		_modifier_name.text = tr("lobby.modifier") % tr(def.name_key)
		_modifier_detail.text = tr(def.detail_key) if def.detail_key != &"" else ""
		_modifier_detail.visible = _modifier_detail.text != ""
		_reroll.text = tr("lobby.reroll")
		_reroll.visible = can and modifier_defs.size() > 1


## Two columns of mode buttons on a narrow sheet, three otherwise.
func fit(narrow: bool) -> void:
	_grid.columns = 2 if narrow else 3
	# An autowrapped label needs a width, or the sheet grows tall.
	_desc.custom_minimum_size.x = 260.0 if narrow else 460.0
	_modifier_detail.custom_minimum_size.x = 200.0 if narrow else 360.0


func _choose_team_win(rule: String) -> void:
	choose(ctx.crew.mode(), rule)


## A host option's switch (#40 D1, D2), added under the mode.
func _switch(node_name: String, id: String) -> CheckButton:
	var sw: CheckButton = CheckButton.new()
	sw.name = node_name
	sw.custom_minimum_size.y = UiTheme.TOUCH_MIN
	sw.toggled.connect(func(on: bool) -> void: set_option(id, on))
	add_child(sw)
	return sw


func _button(node_name: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = UiTheme.TOUCH_MIN
	b.pressed.connect(handler)
	return b
