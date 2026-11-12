extends GdUnitTestSuite
## The lobby's gameplay options (#40 D1, D2, D10, gp-11): the host's two switches and the run
## modifier row in the Game setup sheet, the summary line that names them, and the station
## cells naming bots and guests; the top bar's line of the ship's bots.


func before() -> void:
	I18n.apply("en")


func after() -> void:
	ModePanel.modifier_defs.clear()


func _lobby(host: bool = true) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.crew.lobby[0]["started"] = false
	ctx.crew.host = host
	StationFixture.fleet(ctx, "coop", [StationFixture.SHIP_NAME])
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _fleet(l: LobbyScreen, options: Dictionary) -> void:
	var p: Dictionary = l.ctx.crew.fleet.duplicate(true)
	p.merge(options, true)
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)


static func _modifiers(ids: Array) -> void:
	ModePanel.modifier_defs.clear()
	for id: String in ids:
		var def: RunModifierDef = RunModifierDef.new()
		def.id = StringName(id)
		def.name_key = StringName(id.capitalize())
		def.detail_key = &"lobby.option.fill_bots"
		ModePanel.modifier_defs[id] = def


func _node(l: LobbyScreen, node_name: String) -> Control:
	return l.find_child(node_name, true, false) as Control


# FT: FT-NET-047, FT-NET-048
# The host's switches send GameMode with the mode kept and the option flipped, show what the
# `fleet` event says, and the summary names an option that is on.
func test_host_switches_send_the_options() -> void:
	var l: LobbyScreen = _lobby()
	(_node(l, "GameSetup") as Button).pressed.emit()
	var fill: CheckButton = _node(l, "FillBots") as CheckButton
	var pause: CheckButton = _node(l, "DropPause") as CheckButton
	assert_str(fill.text).is_equal("Fill light stations with bots")
	assert_bool(fill.button_pressed).is_false()
	fill.toggled.emit(true)
	var sent: Array = StationFixture.sent(l.ctx).of("set_mode")[-1][1]
	assert_array(sent).is_equal(["coop", "last_team_standing", -1, false, true])
	_fleet(l, {"fill_bots": true, "drop_pause": true})
	assert_bool(fill.button_pressed).is_true()
	assert_bool(pause.button_pressed).is_true()
	var summary: Label = _node(l, "SetupSummary") as Label
	assert_str(summary.text).is_equal("Co-op · Easy · Pause on drop · Bots fill in")
	_fleet(l, {"started": true})
	assert_bool(fill.disabled).is_true()


# FT: FT-NET-050
# The modifier row shows the rolled modifier's name and detail, with Reroll for the host
# while there is another one; no row without a modifier; a player sees it in the summary.
func test_modifier_row_and_reroll() -> void:
	_modifiers(["ion_storm", "calm"])
	var l: LobbyScreen = _lobby()
	(_node(l, "GameSetup") as Button).pressed.emit()
	assert_bool(_node(l, "Modifier").visible).is_false()
	_fleet(l, {"modifier": "ion_storm"})
	assert_bool(_node(l, "Modifier").visible).is_true()
	assert_str((_node(l, "ModifierName") as Label).text).is_equal("Modifier: Ion Storm")
	var reroll: Button = _node(l, "Reroll") as Button
	assert_bool(reroll.visible).is_true()
	reroll.pressed.emit()
	assert_int(StationFixture.sent(l.ctx).of("reroll_modifier").size()).is_equal(1)
	_modifiers(["ion_storm"])
	_fleet(l, {"modifier": "ion_storm", "fill_bots": false})
	assert_bool(reroll.visible).is_false()
	var player: LobbyScreen = _lobby(false)
	_fleet(player, {"modifier": "ion_storm"})
	assert_str((_node(player, "SetupSummary") as Label).text).is_equal("Co-op · Easy · Ion Storm")


# FT: FT-NET-047, FT-NET-049
# A cell names a stand-in bot for the dropped player, a fill bot and a guest.
func test_cells_name_bots_and_guests() -> void:
	var l: LobbyScreen = _lobby()
	var state: Dictionary = l.ctx.crew.lobby[0]
	state["seats"] = [{"seat": "relay", "name": "Di", "session": 9, "ready": false, "guest": true}]
	state["bots"] = [{"seat": "helm", "for": "Ana"}, {"seat": "comms", "for": ""}]
	l.refresh()
	var crew: Callable = func(id: String) -> String:
		return (_node(l, "Seat_" + id).find_child("Crew", true, false) as Label).text
	assert_str(crew.call("helm")).is_equal("Bot (for Ana)")
	assert_str(crew.call("comms")).is_equal("Bot")
	assert_str(crew.call("relay")).is_equal("Di (guest)")
	assert_str(LobbySeatGrid.bots_line(l.ctx)).is_equal("Helm: Bot (for Ana) · Comms: Bot")
