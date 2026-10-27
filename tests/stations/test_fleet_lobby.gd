extends GdUnitTestSuite
## The multi-ship lobby (#11): the fleet's ships, New ship, teams, the host's mode dialog and
## Start all together; and its phone layout (#28).


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
	assert_str((_button(l, "Entry_helm").find_child("Crew", true, false) as Label).text).is_equal(
		"P1"
	)
	_button(l, "Entry_science").pressed.emit()
	assert_array(_sent(l, "pick")[-1][1]).is_equal([1, "science"])


# FT: FT-GEN-001
# Any player adds a ship while there is room and the universe hasn't started (M4-Q3); the
# new ship takes the first free name and is shown once the server lists it.
func test_new_ship_adds_a_named_ship_up_to_six() -> void:
	var l: LobbyScreen = _lobby()
	var add: Button = _button(l, "NewShip")
	assert_bool(add.visible).is_true()
	add.pressed.emit()
	assert_array(_sent(l, "add_ship")[-1][1]).is_equal(["Merlin"])
	StationFixture.fleet(l.ctx, "coop", [StationFixture.SHIP_NAME, "Heron", "Osprey", "Merlin"])
	assert_int(l.ship).is_equal(3)
	StationFixture.fleet(l.ctx, "coop", ["A", "B", "C", "D", "E", "F"])
	assert_bool(add.visible).is_false()
	StationFixture.fleet(l.ctx, "coop", ["A", "B"], [], true)
	assert_bool(add.visible).is_false()


# FT: FT-MIS-034
# In TEAMS and HOLDOUT the ship buttons name each ship's team and its own crew put their
# ship on team A or B (M4-Q6); another ship's team buttons are read-only; co-op shows none.
func test_crew_put_their_ship_on_a_team() -> void:
	var l: LobbyScreen = _lobby("teams", [0, 1, 1])
	assert_str(_button(l, "Ship_1").text).is_equal("Heron (B)")
	var b: Button = _button(l, "Team_1")
	assert_bool(b.is_visible_in_tree()).is_true()
	assert_bool(_button(l, "Team_0").button_pressed).is_true()
	b.pressed.emit()
	assert_array(_sent(l, "set_team")[-1][1]).is_equal([0, 1])
	_button(l, "Ship_2").pressed.emit()
	assert_bool(_button(l, "Team_1").button_pressed).is_true()
	assert_bool(_button(l, "Team_0").disabled).is_true()
	var coop: LobbyScreen = _lobby("coop")
	assert_bool(_button(coop, "Team_0").is_visible_in_tree()).is_false()


# FT: FT-MIS-031, FT-GEN-002, FT-MIS-034
# The host's Mode dialog offers co-op and the three PvP types plus holdout, each with a one-line
# description, and in TEAMS the win rule; a choice goes to the server. Others see it
# read-only.
func test_host_picks_the_mode_and_team_win_rule() -> void:
	var l: LobbyScreen = _lobby("coop", [], true)
	l.size = Vector2(1280, 720)
	l.refresh()
	var mode: Button = _button(l, "ModeButton")
	assert_str(mode.text).is_equal("Mode: Co-op")
	mode.pressed.emit()
	for m: String in ModeDialog.MODES:
		assert_bool(_button(l, "Mode_" + m).disabled).is_false()
	assert_str(_button(l, "Mode_last_standing").text).is_equal("Last ship standing")
	_button(l, "Mode_teams").pressed.emit()
	assert_array(_sent(l, "set_mode")[-1][1]).is_equal(["teams", "last_team_standing", -1])
	var p: Dictionary = StationFixture.fleet(l.ctx, "teams", ["A", "B"], [0, 1])
	assert_str(FleetMessages.check(NetProtocol.EVENT_FLEET, p)).is_empty()
	assert_bool((l.find_child("TeamWin", true, false) as Control).visible).is_true()
	_button(l, "Win_first_to_finish").pressed.emit()
	assert_array(_sent(l, "set_mode")[-1][1]).is_equal(["teams", "first_to_finish", -1])
	assert_str(mode.text).is_equal("Mode: Teams (Last team standing)")
	# A phone shows just the mode's name.
	l.size = Vector2(390, 844)
	l.refresh()
	assert_str(mode.text).is_equal("Teams")
	StationFixture.fleet(l.ctx, "holdout", ["A", "B"], [0, 1])
	assert_str((l.find_child("ModeDesc", true, false) as Label).text).contains("3 lives")
	var guest: LobbyScreen = _lobby("race")
	assert_bool(_button(guest, "Mode_coop").disabled).is_true()
	_button(guest, "Mode_coop").pressed.emit()
	assert_array(_sent(guest, "set_mode")).is_empty()
	assert_str((guest.find_child("ModeDesc", true, false) as Label).text).contains("host")


# FT: FT-GEN-001
# Start is pressed per ship; the universe starts all together (M4-Q4), so a ship that
# pressed it names the ships still to press it, and the lobby stays until `fleet` says
# the universe started.
func test_start_waits_for_the_other_ships() -> void:
	var l: LobbyScreen = _lobby()
	var p: Dictionary = StationFixture.fleet(l.ctx)
	p["ships"][0]["started"] = true
	p["waiting"] = [1, 2]
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	l.ctx.crew.lobby[0]["started"] = true
	l.refresh()
	var start: Button = _button(l, "Start")
	assert_bool(start.visible).is_true()
	assert_bool(start.disabled).is_true()
	assert_str(start.text).is_equal("Waiting for Heron, Osprey")
	assert_bool(l.ctx.crew.is_started()).is_false()
	p["started"] = true
	p["waiting"] = []
	l.ctx.crew.handle_event({"type": "fleet", "payload": p}, 0)
	assert_bool(l.ctx.crew.is_started()).is_true()


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
# ship row keeps its own row, Start joins the bottom row, and every tap target is at least
# 48 px, 8 px from the next, inside the safe area and above the gesture band (TapAudit).
func test_phone_landscape_lobby_meets_the_touch_rules() -> void:
	var l: LobbyScreen = _lobby("teams", [0, 1, 1], true)
	var old: Vector2i = get_tree().root.size
	LayoutMode.forced = LayoutMode.Kind.PHONE
	SafeArea.simulate([47, 0, 47, 21])
	LayoutMode.apply(get_tree().root)
	get_tree().root.size = Vector2i(844, 390)
	l.size = Vector2(844, 390)
	for i: int in 4:
		await get_tree().process_frame
	assert_object(_button(l, "Start").get_parent()).is_same(l.find_child("Difficulty", true, false))
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
