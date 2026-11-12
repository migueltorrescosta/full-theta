extends GdUnitTestSuite
## The multi-ship lobby (#11, #37 C1): the fleet's ships, the host's Game setup sheet (mode,
## teams, Add a ship), Ready and the host's one Start; and its phone layout (#28).


func before() -> void:
	I18n.apply("en")


func _lobby(mode: String = "coop", teams: Array = [], host: bool = false) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.crew.lobby[0]["started"] = false
	ctx.crew.host = host
	StationFixture.fleet(ctx, mode, [StationFixture.SHIP_NAME, "Heron", "Osprey"], teams)
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _button(l: LobbyScreen, node_name: String) -> Button:
	return l.find_child(node_name, true, false) as Button


func _sent(l: LobbyScreen, method: String) -> Array:
	return StationFixture.sent(l.ctx).of(method)


# FT: FT-GEN-001
# The fixture's payload is the contract's `fleet` shape; the lobby shows a button per ship
# of it, the player's own pressed, and choosing another shows that ship's seats and
# coverage from its fleet row; a pick there names that ship.
func test_lobby_lists_the_fleet_ships_with_their_own_picks() -> void:
	var l: LobbyScreen = _lobby()
	var p: Dictionary = StationFixture.fleet(l.ctx)
	assert_str(FleetMessages.check(NetProtocol.EVENT_FLEET, p)).is_empty()
	for i: int in 3:
		assert_object(_button(l, "Ship_%d" % i)).is_not_null()
	assert_str(_button(l, "Ship_1").text).is_equal("Heron")
	assert_bool(_button(l, "Ship_0").button_pressed).is_true()
	_button(l, "Ship_1").pressed.emit()
	assert_int(l.ship).is_equal(1)
	assert_str((l.find_child("Coverage", true, false) as Label).text).contains("Weapons")
	assert_str((_button(l, "Seat_helm").find_child("Crew", true, false) as Label).text).is_equal(
		"P1"
	)
	_button(l, "Seat_science").pressed.emit()
	assert_array(_sent(l, "pick")[-1][1]).is_equal([1, "science"])


# FT: FT-GEN-001
# The host adds a ship from its Game setup sheet while there is room and the game hasn't
# started (M4-Q3, #37 C1); the new ship takes the first free name and is shown once the server
# lists it. A player has no Game setup and no way to add one.
func test_the_host_adds_a_named_ship_up_to_six() -> void:
	var l: LobbyScreen = _lobby("coop", [], true)
	var add: Button = _button(l, "AddShip")
	assert_bool(_button(l, "GameSetup").visible).is_true()
	_button(l, "GameSetup").pressed.emit()
	assert_bool(add.visible).is_true()
	add.pressed.emit()
	assert_array(_sent(l, "add_ship")[-1][1]).is_equal(["Merlin"])
	StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME, "Heron", "Osprey", "Merlin"])
	assert_int(l.ship).is_equal(3)
	StationFixture.fleet(l.ctx, "coop", ["A", "B", "C", "D", "E", "F"])
	assert_bool(add.visible).is_false()
	StationFixture.fleet(l.ctx, "coop", ["A", "B"], [], true)
	assert_bool(add.visible).is_false()
	var guest: LobbyScreen = _lobby()
	assert_bool(_button(guest, "GameSetup").visible).is_false()


# FT: FT-MIS-034
# In TEAMS and HOLDOUT the ship buttons name each ship's team, and the host puts any ship on
# team A or B in the Game setup sheet (M4-Q6, #37 C1); co-op lists no teams there.
func test_the_host_puts_ships_on_teams() -> void:
	var l: LobbyScreen = _lobby("teams", [0, 1, 1], true)
	assert_str(_button(l, "Ship_1").text).is_equal("Heron (B)")
	_button(l, "GameSetup").pressed.emit()
	var row: Control = l.find_child("ShipRow_2", true, false)
	assert_bool((row.get_node("Team_1") as Button).button_pressed).is_true()
	(row.get_node("Team_0") as Button).pressed.emit()
	assert_array(_sent(l, "set_team")[-1][1]).is_equal([2, 0])
	var coop: LobbyScreen = _lobby("coop", [], true)
	assert_object(coop.find_child("ShipRow_0", true, false)).is_null()
	assert_object(coop.find_child("Team_0", true, false)).is_null()


# FT: FT-MIS-031, FT-GEN-002, FT-MIS-034
# The host's Game setup sheet offers co-op and the three PvP types plus holdout, each with a
# one-line description, and in TEAMS the win rule; a choice goes to the server. Everyone sees
# the one-line summary (#37 C1: "Co-op · Easy"); a player gets no sheet.
func test_host_picks_the_mode_and_team_win_rule() -> void:
	var l: LobbyScreen = _lobby("coop", [], true)
	l.size = Vector2(1280, 720)
	l.refresh()
	var summary: Label = l.find_child("SetupSummary", true, false)
	assert_str(summary.text).is_equal("Co-op · Easy")
	_button(l, "GameSetup").pressed.emit()
	for m: String in ModePanel.MODES:
		assert_bool(_button(l, "Mode_" + m).disabled).is_false()
	assert_str(_button(l, "Mode_last_standing").text).is_equal("Last ship standing")
	_button(l, "Mode_teams").pressed.emit()
	assert_array(_sent(l, "set_mode")[-1][1]).is_equal(["teams", "last_team_standing", -1])
	var p: Dictionary = StationFixture.fleet(l.ctx, "teams", ["A", "B"], [0, 1])
	assert_str(FleetMessages.check(NetProtocol.EVENT_FLEET, p)).is_empty()
	assert_bool((l.find_child("TeamWin", true, false) as Control).visible).is_true()
	_button(l, "Win_first_to_finish").pressed.emit()
	assert_array(_sent(l, "set_mode")[-1][1]).is_equal(["teams", "first_to_finish", -1])
	assert_str(summary.text).is_equal("Teams · Easy")
	StationFixture.fleet(l.ctx, "holdout", ["A", "B"], [0, 1])
	assert_str((l.find_child("ModeDesc", true, false) as Label).text).contains("3 lives")
	var guest: LobbyScreen = _lobby("race")
	assert_bool(_button(guest, "GameSetup").visible).is_false()
	assert_str((guest.find_child("SetupSummary", true, false) as Label).text).is_equal(
		"Race · Easy"
	)


# FT: FT-GEN-001
# The host's one Start for the whole fleet (M4-Q4, #37 C1): greyed with the ship that isn't
# covered yet, then with the players who aren't Ready, and lit once everyone is; the lobby
# stays until `fleet` says the universe started. The host has no Ready of its own.
func test_the_hosts_start_waits_for_every_ship_and_player() -> void:
	var l: LobbyScreen = _lobby("coop", [], true)
	var p: Dictionary = StationFixture.fleet(l.ctx)
	var start: Button = _button(l, "Start")
	assert_bool(start.visible).is_true()
	assert_bool(_button(l, "Ready").visible).is_false()
	assert_bool(start.disabled).is_true()
	assert_str(start.text).is_equal("Waiting for Heron")
	for row: Dictionary in p["ships"]:
		row["covered"] = true
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_str(start.text).is_equal("Waiting for P1, P2")
	for row: Dictionary in p["ships"]:
		row["seats"][0]["ready"] = true
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_bool(start.disabled).is_false()
	assert_str(start.text).is_equal("Start")
	start.pressed.emit()
	assert_array(_sent(l, "start")).is_equal([["start", []]])
	assert_bool(l.ctx.crew.is_started()).is_false()
	p["started"] = true
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_bool(l.ctx.crew.is_started()).is_true()


# FT: FT-GEN-001
# A crew player sees Ready, not Start, while the host is here (#37 C1): Ready sends the toggle
# and shows a tick once the server holds it. With no host connected, a Ready crew player gets
# Start; Captain and viewers get neither.
func test_a_player_has_ready_and_without_a_host_start() -> void:
	var l: LobbyScreen = _lobby()
	var p: Dictionary = StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME])
	var ready: Button = _button(l, "Ready")
	assert_bool(ready.visible).is_true()
	assert_bool(_button(l, "Start").visible).is_false()
	assert_str(ready.text).is_equal("Ready")
	ready.pressed.emit()
	assert_array(_sent(l, "set_ready")[-1][1]).is_equal([true])
	p["ships"][0]["seats"] = [
		{"name": "Me", "seat": "helm", "session": StationFixture.SESSION, "ready": true}
	]
	l.ctx.crew.lobby.erase(0)
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_bool(ready.button_pressed).is_true()
	assert_str(ready.text).is_equal("✓ Ready")
	var crew: Label = _button(l, "Seat_helm").find_child("Crew", true, false)
	assert_str(crew.text).is_equal("✓ Me")
	assert_bool(_button(l, "Start").visible).is_false()
	p["host"] = false
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_bool(_button(l, "Start").visible).is_true()
	ready.pressed.emit()
	assert_array(_sent(l, "set_ready")[-1][1]).is_equal([false])
	var captain: LobbyScreen = _lobby()
	captain.ctx.crew.seat = "captain"
	captain.refresh()
	assert_bool(_button(captain, "Ready").visible).is_false()
	assert_bool(_button(captain, "Start").visible).is_false()


# FT: FT-GEN-001
# A game of one ship shows no ship row and no Back to ships (#37 C1); a second ship brings both.
func test_one_ship_shows_no_ship_row() -> void:
	var l: LobbyScreen = _lobby()
	StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME])
	var rows: Callable = func() -> bool:
		var flow: Control = l.find_child("Ships", true, false)
		var strip: Control = l.find_child("ShipScroll", true, false)
		return flow.visible or strip.visible
	assert_bool(rows.call()).is_false()
	assert_bool(_button(l, "BackToShips").visible).is_false()
	StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME, "Heron"])
	assert_bool(rows.call()).is_true()
	assert_bool(_button(l, "BackToShips").visible).is_true()


# FT: FT-GEN-001
# A refused lobby request (a full fleet) says why under the grid until the next change.
func test_a_refused_ship_add_says_why() -> void:
	var l: LobbyScreen = _lobby()
	var e: Dictionary = {
		"type": "request_rejected", "payload": {"reason": FleetMessages.FLEET_FULL}
	}
	l.ctx.crew.handle_event(e, 0)
	assert_str((l.find_child("SummaryRole", true, false) as Label).text).contains("most ships")
	StationFixture.fleet(l.ctx)
	assert_str((l.find_child("SummaryRole", true, false) as Label).text).not_contains("most ships")


# FT: FT-GEN-001
# A phone in landscape (844 x 390 with 47 px side insets and a 21 px bottom inset, #28): the
# ship row keeps its own row, Start joins the setup row, and every tap target is at least
# 48 px, 8 px from the next, inside the safe area and above the gesture band (TapAudit).
func test_phone_landscape_lobby_meets_the_touch_rules() -> void:
	var l: LobbyScreen = _lobby("teams", [0, 1, 1], true)
	var old: Vector2i = get_tree().root.size
	LayoutMode.forced = LayoutMode.Kind.PHONE
	SafeArea.simulate([47, 0, 47, 21])
	LayoutMode.apply(get_tree().root)
	get_tree().root.size = Vector2i(844, 390)
	# The suite's node sits outside the window's theme: give the lobby the phone's own.
	l.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
	l.size = Vector2(844, 390)
	for i: int in 4:
		await get_tree().process_frame
	assert_object(_button(l, "Start").get_parent()).is_same(l.find_child("Setup", true, false))
	var report: Dictionary = TapAudit.check(l)
	SafeArea.simulate([])
	LayoutMode.forced = -1
	get_tree().root.size = old
	LayoutMode.apply(get_tree().root)
	assert_array(report["targets"]).is_not_empty()
	for key: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
		assert_array(report[key]).override_failure_message("%s: %s" % [key, report[key]]).is_empty()
	for t: Dictionary in report["targets"]:
		var r: Rect2 = t["rect"]
		assert_float(minf(r.size.x, r.size.y)).override_failure_message(t["text"]).is_greater_equal(
			48.0
		)


# FT: FT-NET-021
# C3, R24-6: a greyed Start says what it waits for, on the button, whatever the form.
func test_a_greyed_start_names_what_it_waits_for() -> void:
	var l: LobbyScreen = _lobby("coop", [], true)
	StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME])
	var start: Button = _button(l, "Start")
	var state: Dictionary = l.ctx.crew.ship_state(l.ship).duplicate()
	state.merge({"covered": false, "uncovered": ["relay", "comms"], "crew": 2, "min_crew": 3}, true)
	assert_str(l.coverage_blocker(state)).is_equal("Need Relay, Comms")
	state["uncovered"] = []
	assert_str(l.coverage_blocker(state)).is_equal("Need 1 more player")
	state["crew"] = 1
	assert_str(l.coverage_blocker(state)).is_equal("Need 2 more players")
	assert_str(l.start_blocker()).is_empty()
	l.ctx.crew.lobby[l.ship].merge({"covered": false, "uncovered": ["relay"], "crew": 2}, true)
	l.refresh()
	assert_bool(start.disabled).is_true()
	assert_str(start.text).is_equal("Need Relay")
	# w5: a text too long for the button wraps in a smaller font, never cut.
	start.size = Vector2(200.0, start.size.y)
	l.ctx.crew.lobby[l.ship].merge({"uncovered": ["relay", "comms", "science"]}, true)
	l.refresh()
	assert_int(start.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
	assert_int(start.get_theme_font_size("font_size")).is_equal(LobbyScreen.START_WRAP_SIZE)
	start.size = Vector2(1200.0, start.size.y)
	assert_int(start.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)


# FT: FT-NET-003
# C1, R24-2: a player's lobby button reads Leave and leaves; the host's reads End game and asks
# before it ends the game for everyone.
func test_the_hosts_lobby_button_ends_the_game_after_a_confirm() -> void:
	var guest: LobbyScreen = _lobby()
	var left: Array[int] = [0]
	guest.menu_requested.connect(func() -> void: left[0] += 1)
	assert_str(_button(guest, "MainMenu").text).is_equal("Leave")
	_button(guest, "MainMenu").pressed.emit()
	assert_int(left[0]).is_equal(1)
	var host: LobbyScreen = _lobby("coop", [], true)
	host.menu_requested.connect(func() -> void: left[0] += 1)
	var dialog: ConfirmationDialog = host.find_child("EndDialog", true, false)
	assert_str(_button(host, "MainMenu").text).is_equal("End game")
	_button(host, "MainMenu").pressed.emit()
	assert_int(left[0]).is_equal(1)
	assert_bool(dialog.visible).is_true()
	dialog.confirmed.emit()
	assert_int(left[0]).is_equal(2)
