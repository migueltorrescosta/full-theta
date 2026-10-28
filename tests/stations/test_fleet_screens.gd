extends GdUnitTestSuite
## The multi-ship screens (#11): the scoreboard, the viewer handover notice, the give-up
## (forfeit) and relaunch prompts, the cross-ship takeover in a pause, and the client
## shell's switch to the scoreboard. Events are built with FleetMessages, the server's
## builders, so the client reads the contract's shapes.


func before() -> void:
	I18n.apply("en")


func _ctx(mode: String = "race", entry: String = "helm") -> StationContext:
	var ctx: StationContext = StationFixture.context(entry)
	StationFixture.fleet(ctx, mode, [StationFixture.SHIP_NAME, "Heron", "Osprey"], [0, 1, 1], true)
	return ctx


func _event(ctx: StationContext, type: String, p: Dictionary) -> void:
	assert_str(FleetMessages.check(type, p)).is_empty()
	ctx.crew.handle_event({"type": type, "payload": p}, StationFixture.NOW_MS)


func _rows() -> Array:
	return [
		FleetMessages.scoreboard_row(0, StationFixture.SHIP_NAME, 0, "destroyed", 2, 300.0, 1),
		FleetMessages.scoreboard_row(1, "Heron", 1, "in_play", 3, 412.0, 2),
		FleetMessages.scoreboard_row(2, "Osprey", 1, "finished", 4, 380.0, 0),
	]


func _label(root: Node, node_name: String) -> Label:
	return root.find_child(node_name, true, false) as Label


func _scoreboard(ctx: StationContext) -> ScoreboardScreen:
	var s: ScoreboardScreen = auto_free(ScoreboardScreen.new())
	s.setup(ctx)
	add_child(s)
	return s


# FT: FT-MIS-030, FT-NET-010
# The live scoreboard (M4-Q9): per ship its name, status, encounters done, time and, in PvP,
# kills; the team column only with teams; no hull and no positions. The player's own ship
# is out, so the line under the title says so.
func test_scoreboard_shows_status_and_progress_only() -> void:
	var ctx: StationContext = _ctx("race")
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 0))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD))
	_event(ctx, NetProtocol.EVENT_SCOREBOARD, FleetMessages.scoreboard(_rows()))
	var s: ScoreboardScreen = _scoreboard(ctx)
	assert_array(s.columns()).is_equal(["ship", "state", "encounters", "time", "kills"])
	assert_str(_label(s, "Row1_ship").text).is_equal("Heron")
	assert_str(_label(s, "Row1_state").text).is_equal("In play")
	assert_str(_label(s, "Row0_state").text).is_equal("Out")
	assert_str(_label(s, "Row2_state").text).is_equal("Finished")
	assert_str(_label(s, "Row1_time").text).is_equal("6:52")
	assert_str(_label(s, "Row1_kills").text).is_equal("2")
	assert_str(_label(s, "Title").text).is_equal("Scoreboard")
	assert_str(_label(s, "Sub").text).is_equal("Kestrel is out: destroyed.")
	for l: Node in s.find_children("*", "Label", true, false):
		assert_str((l as Label).text.to_lower()).not_contains("hull")
	StationFixture.fleet(ctx, "teams", ["A", "B"], [0, 1], true)
	assert_array(s.columns()).contains(["team"])
	StationFixture.fleet(ctx, "coop", ["A", "B"], [], true)
	assert_array(s.columns()).not_contains(["kills", "team"])


# FT: FT-MIS-014
# Session over (PvP): the title names the winner by the mode's reason: a ship, a team, or the
# holdout's time.
func test_scoreboard_title_names_the_winner() -> void:
	var ctx: StationContext = _ctx("race")
	var s: ScoreboardScreen = _scoreboard(ctx)
	var over: Dictionary = {
		"reason": "first_to_finish", "winners": [1], "team": -1, "held_s": 0.0, "time_s": 600.0
	}
	_event(ctx, NetProtocol.EVENT_SESSION_OVER, over)
	assert_str(_label(s, "Title").text).is_equal("Heron wins!")
	assert_str(_label(s, "Sub").text).is_equal("Game time 10:00.")
	over["reason"] = "last_team_standing"
	over["team"] = 1
	_event(ctx, NetProtocol.EVENT_SESSION_OVER, over)
	assert_str(_label(s, "Title").text).is_equal("Team B wins!")
	over["reason"] = "holdout_over"
	over["held_s"] = 245.0
	_event(ctx, NetProtocol.EVENT_SESSION_OVER, over)
	assert_str(_label(s, "Title").text).is_equal("Team B held for 4:05")


# FT: FT-MIS-030
# A handover to a friendly ship's main screen shows a notice naming the ship that is out, why,
# and the ship now watched; OK hides it. A handover to the scoreboard shows no notice.
func test_handover_notice_names_both_ships() -> void:
	var ctx: StationContext = _ctx("teams")
	var n: HandoverNotice = auto_free(HandoverNotice.new())
	n.setup(ctx)
	add_child(n)
	assert_bool(n.visible).is_false()
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(1, "forfeit", 0))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(1, 2))
	assert_bool(n.visible).is_true()
	assert_str(_label(n, "Text").text).is_equal(
		"Heron is out: gave up. You're watching Osprey now."
	)
	(n.find_child("Ok", true, false) as Button).pressed.emit()
	assert_bool(n.visible).is_false()
	n.refresh()
	assert_bool(n.visible).is_false()
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(1, FleetMessages.TO_SCOREBOARD))
	assert_bool(n.visible).is_false()


# FT: FT-MIS-016
# PvP give-up (M4-Q10): once a crewmate votes outside a pause, the crew see the vote and cast
# or take back theirs; the host also gets Give up now. The menu offers the forfeit vote in
# PvP and the abandon vote in co-op.
func test_forfeit_prompt_shows_the_vote_outside_a_pause() -> void:
	var ctx: StationContext = _ctx("race")
	var p: VotePrompt = auto_free(VotePrompt.new())
	p.setup(ctx, VotePrompt.Kind.FORFEIT)
	add_child(p)
	assert_bool(p.visible).is_false()
	assert_str(ctx.crew.abandon_control()).is_equal("settings.forfeit_vote")
	var votes: Dictionary = {"ship": 0, "voters": ["Bo"], "sessions": [99], "needed": 2}
	ctx.crew.handle_event({"type": "abandon_votes", "payload": votes}, 0)
	assert_bool(p.visible).is_true()
	assert_str(_label(p, "Votes").text).is_equal("Votes 1/2: Bo")
	(p.find_child("Vote", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("vote_abandon")[-1][1]).is_equal([0, true])
	assert_object(p.find_child("GiveUp", true, false)).is_null()
	ctx.crew.host = true
	p.refresh()
	(p.find_child("GiveUp", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("abandon")[-1][1]).is_equal([0])
	# In a pause the overlay holds the vote; once out of play, no prompt.
	ctx.crew.handle_event({"type": "pause", "payload": {"ship": 0, "uncovered": ["helm"]}}, 0)
	assert_bool(p.visible).is_false()
	ctx.crew.handle_event({"type": "resume", "payload": {"ship": 0}}, 0)
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "forfeit", 0))
	assert_bool(p.visible).is_false()
	assert_str(ctx.crew.abandon_control()).is_empty()
	var coop: StationContext = _ctx("coop")
	assert_str(coop.crew.abandon_control()).is_equal("settings.abandon_vote")


# FT: FT-MIS-011
# Relaunch (M4-Q2): an eliminated ship whose side has lives left offers its crew the
# relaunch vote with the lives left; a side with none offers nothing; `relaunched` clears it.
# On the scoreboard the vote sits in its layout; over a friendly ship's screen it floats.
func test_relaunch_prompt_offers_the_vote_while_lives_last() -> void:
	var ctx: StationContext = _ctx("holdout")
	var floating: VotePrompt = auto_free(VotePrompt.new())
	floating.setup(ctx, VotePrompt.Kind.RELAUNCH)
	add_child(floating)
	var s: ScoreboardScreen = _scoreboard(ctx)
	var p: VotePrompt = s.relaunch
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 2))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD))
	assert_bool(p.visible).is_true()
	assert_bool(floating.visible).is_false()
	assert_str(_label(p, "Title").text).is_equal("Kestrel is out. 2 lives left.")
	(p.find_child("Relaunch", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("vote_relaunch")[-1][1]).is_equal([0, true])
	_event(ctx, NetProtocol.EVENT_RELAUNCH_VOTES, FleetMessages.relaunch_votes(0, ["Ana"], 2))
	assert_str(_label(p, "Votes").text).is_equal("Relaunch votes 1/2: Ana")
	assert_str((p.find_child("Relaunch", true, false) as Button).text).is_equal("Take back my vote")
	_event(ctx, NetProtocol.EVENT_RELAUNCHED, FleetMessages.relaunched(0, 1))
	assert_bool(p.visible).is_false()
	assert_bool(ctx.crew.handover.is_empty()).is_true()
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", -1))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, 2))
	assert_bool(floating.visible).is_true()
	assert_str(_label(floating, "Title").text).contains("as often as you like")
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 0))
	assert_bool(floating.visible).is_false()


# FT: FT-NET-042
# Takeover in a pause (M4-Q8): an allied ship's player sees the paused ship's uncovered
# stations and takes one; an enemy ship's pause offers nothing. The ship's side sees who took
# it as a toast.
func test_allied_players_take_over_a_paused_ship() -> void:
	var ctx: StationContext = _ctx("teams")
	ctx.crew.handle_event({"type": "picked", "payload": {"ship": 1, "entry": "helm"}}, 0)
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	ctx.crew.handle_event({"type": "pause", "payload": {"ship": 2, "uncovered": ["science"]}}, 0)
	assert_bool(o.visible).is_true()
	var take: Button = o.find_child("Takeover_science", true, false)
	assert_str(take.text).is_equal("Take Science on Osprey")
	take.pressed.emit()
	assert_array(StationFixture.sent(ctx).of("takeover")[-1][1]).is_equal([2, "science"])
	assert_object(o.find_child("Vote", true, false)).is_null()
	ctx.crew.handle_event({"type": "resume", "payload": {"ship": 2}}, 0)
	ctx.crew.handle_event({"type": "pause", "payload": {"ship": 0, "uncovered": ["science"]}}, 0)
	assert_object(o.find_child("Takeover_science", true, false)).is_null()
	var toasts: Array = []
	ctx.crew.toast.connect(func(key: String, args: Dictionary) -> void: toasts.append([key, args]))
	_event(ctx, NetProtocol.EVENT_TAKEOVER, FleetMessages.takeover(2, "science", "Bo", 1))
	assert_str(toasts[-1][0]).is_equal("toast.takeover")
	assert_str(tr(toasts[-1][0]).format(toasts[-1][1])).is_equal("Bo took Science on Osprey.")


# FT: FT-MIS-030
# The scoreboard is for a session handed over to it, and in PvP to everyone once
# the session is over; in co-op the outcome card keeps the run's end.
func test_who_sees_the_scoreboard() -> void:
	var crew: CrewState = _ctx("race").crew
	assert_bool(crew.on_scoreboard()).is_false()
	crew.handle_event(
		{"type": "handover", "payload": FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD)}, 0
	)
	assert_bool(crew.on_scoreboard()).is_true()
	var pvp: CrewState = _ctx("race").crew
	var over: Dictionary = {
		"reason": "last_standing", "winners": [1], "team": -1, "held_s": 0.0, "time_s": 9.0
	}
	pvp.handle_event({"type": "session_over", "payload": over}, 0)
	assert_bool(pvp.on_scoreboard()).is_true()
	var coop: CrewState = _ctx("coop").crew
	over["reason"] = "objective"
	coop.handle_event({"type": "session_over", "payload": over}, 0)
	assert_bool(coop.on_scoreboard()).is_false()


# FT: FT-MIS-033
# The debrief names a last-ship-standing raider wave (M4-Q7) with its number and size.
func test_debrief_names_a_raider_wave() -> void:
	var d: DirectorDecision = DirectorDecision.new()
	d.tick = 7200
	d.ship = 0
	d.kind = DirectorDecision.Kind.RAIDER_WAVE
	d.reason_key = "director.reason.raider_wave"
	d.reason_args = {"wave": 2, "count": 3}
	var line: String = DebriefCard._decision_line(d.to_dict())
	assert_str(line).is_equal(
		"2:00  Sent raiders: Raider wave 2: 3 raiders at every ship still flying"
	)


# FT: FT-MIS-030
# On a phone upright the widest table (teams and kills) fits the screen: no sideways scroll
# (l5_ph_scoreboard cut Kills and Time, #28).
func test_scoreboard_fits_a_portrait_phone() -> void:
	var ctx: StationContext = _ctx("teams")
	_event(ctx, NetProtocol.EVENT_SCOREBOARD, FleetMessages.scoreboard(_rows()))
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(390, 844)
	add_child(vp)
	var s: ScoreboardScreen = ScoreboardScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	for i: int in 3:
		await get_tree().process_frame
	assert_int(s.columns().size()).is_equal(6)
	var table: Control = s.find_child("Table", true, false)
	var scroll: ScrollContainer = table.get_parent()
	assert_float(table.get_combined_minimum_size().x).is_less_equal(scroll.size.x)
	assert_str(_label(s, "Head_encounters").text).is_equal("Enc.")
