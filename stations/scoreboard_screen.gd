class_name ScoreboardScreen
extends Control
## The live scoreboard (#11; D91, D266 proposed, M4-Q9, FT-MIS-030, FT-NET-010): where an
## eliminated crew goes when no friendly ship is left, and every PvP session once it is
## over. One row per ship: its name, its team (TEAMS and HOLDOUT), in play / finished /
## out, encounters done, time and, in PvP, kills. No hull and no positions. The title says
## why the player is here: the session's result, or that their ship is out.

## The player wants out of the session (Main menu).
signal menu_requested

## The crew changes the scoreboard depends on.
const KINDS: Array[StringName] = [
	&"scoreboard", &"session_over", &"handover", &"fleet", &"eliminated", &"relaunch"
]
const TEAM_LETTERS: Array[String] = ["A", "B"]

var ctx: StationContext
## The relaunch vote of the player's eliminated ship, above the rows (M4-Q2).
var relaunch: VotePrompt

var _title: Label
var _sub: Label
var _table: GridContainer
var _menu: Button


func setup(context: StationContext) -> void:
	ctx = context
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = "TitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	_menu = Button.new()
	_menu.name = "MainMenu"
	_menu.custom_minimum_size = Vector2(0, UiTheme.TOUCH_MIN + 4)
	_menu.pressed.connect(menu_requested.emit)
	head.add_child(_menu)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.theme_type_variation = "DimLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_sub)
	relaunch = VotePrompt.new()
	relaunch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(relaunch)
	relaunch.setup(ctx, VotePrompt.Kind.RELAUNCH, false)
	# The rows scroll, both ways on a narrow screen, so the title row keeps its width.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_table = GridContainer.new()
	_table.name = "Table"
	_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_table.add_theme_constant_override("h_separation", 32)
	_table.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_table)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


## The columns: ship, team (with teams), status, encounters, time, kills (PvP).
func columns() -> Array[String]:
	var out: Array[String] = ["ship"]
	if ctx.crew.has_teams():
		out.append("team")
	out.append_array(["state", "encounters", "time"])
	if ctx.crew.is_pvp():
		out.append("kills")
	return out


## The title: the session's result once it is over, else "Scoreboard".
func title_text() -> String:
	var over: Dictionary = ctx.crew.session_over
	if over.is_empty():
		return tr("score.title")
	var winners: Array = over.get("winners", [])
	var team: int = int(over.get("team", -1))
	var text: String = tr("score.over")
	match str(over.get("reason", "")):
		"holdout_over":
			text = tr("score.held") % clock(float(over.get("held_s", 0.0)))
		"all_lost":
			text = tr("score.all_lost")
		"objective":
			text = tr("score.objective")
		_:
			if team >= 0:
				text = tr("score.team_wins") % TEAM_LETTERS[clampi(team, 0, 1)]
			elif winners.size() == 1:
				text = tr("score.ship_wins") % ctx.crew.ship_name(int(winners[0]))
	return text


## The line under the title: why this player is here, or the session's length.
func sub_text() -> String:
	var parts: PackedStringArray = []
	var home: int = ctx.crew.home_ship()
	var out: Dictionary = ctx.crew.eliminated.get(home, {})
	if not out.is_empty():
		parts.append(
			tr("score.your_ship_out") % [ctx.crew.ship_name(home), tr("out." + str(out["reason"]))]
		)
	if not ctx.crew.session_over.is_empty():
		parts.append(tr("score.time") % clock(float(ctx.crew.session_over.get("time_s", 0.0))))
	return " ".join(parts)


## "4:05" for 245 s.
static func clock(seconds: float) -> String:
	var s: int = maxi(int(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## One row's cells, in column order.
func row_cells(row: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for c: String in columns():
		match c:
			"ship":
				out.append(str(row.get("name", "")))
			"team":
				out.append(TEAM_LETTERS[clampi(int(row.get("team", 0)), 0, 1)])
			"state":
				out.append(tr("score.state." + str(row.get("state", ""))))
			"encounters":
				out.append(str(int(row.get("encounters", 0))))
			"time":
				out.append(clock(float(row.get("time_s", 0.0))))
			"kills":
				out.append(str(int(row.get("kills", 0))))
	return out


func refresh() -> void:
	_title.text = title_text()
	_sub.text = sub_text()
	_sub.visible = _sub.text != ""
	_menu.text = tr("lobby.menu")
	for c: Node in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	var cols: Array[String] = columns()
	_table.columns = cols.size()
	for c: String in cols:
		var h: Label = _cell(tr("score.col." + c), "DimLabel")
		h.name = "Head_" + c
	var home: int = ctx.crew.home_ship()
	for row: Dictionary in ctx.crew.scoreboard:
		var cells: Array[String] = row_cells(row)
		for i: int in cells.size():
			var l: Label = _cell(cells[i], "HeadingLabel" if i == 0 else "")
			l.name = "Row%d_%s" % [int(row.get("ship", -1)), cols[i]]
			if int(row.get("ship", -1)) == home:
				l.add_theme_color_override("font_color", Palette.color("accent"))
			elif str(row.get("state", "")) == "destroyed":
				l.add_theme_color_override("font_color", Palette.color("text_dim"))


func _cell(text: String, variation: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	_table.add_child(l)
	return l


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and ctx != null and _title != null:
		refresh()
