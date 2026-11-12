extends GdUnitTestSuite
## OutcomeCard (D178) on fixtures, and the run reset through ClientShell against a real
## server (L3): outcome, card, Run again, back to the lobby, Start again.

const SETTINGS: String = "user://test_outcome_card.cfg"
const SLOW_MS: int = 15_000

var _h: NetHarness


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	_h = NetHarness.new(self)


func after_test() -> void:
	await _h.free_all()
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _card(seat: String, host: bool = false) -> OutcomeCard:
	var ctx: StationContext = StationFixture.context(seat)
	ctx.crew.host = host
	var o: OutcomeCard = auto_free(OutcomeCard.new())
	o.setup(ctx)
	add_child(o)
	return o


func _over(o: OutcomeCard, outcome: String) -> void:
	var p: Dictionary = {"ship": 0, "outcome": outcome, "time_s": 222.5, "hull": 0.637}
	o.ctx.crew.handle_event({"type": "ship_outcome", "payload": p}, 0)
	var votes: Dictionary = {"ship": 0, "voters": [], "needed": 2}
	o.ctx.crew.handle_event({"type": "run_votes", "payload": votes}, 0)


func _text(o: OutcomeCard, node: String) -> String:
	return (o.find_child(node, true, false) as Label).text


# FT: FT-M1-012
# Hidden during the run; Victory or Ship lost with time and hull after it; crew cast and
# withdraw a vote; the card goes at the reset.
func test_card_shows_the_outcome_and_crew_vote() -> void:
	var o: OutcomeCard = _card("tactical")
	assert_bool(o.visible).is_false()
	_over(o, "win")
	assert_bool(o.visible).is_true()
	assert_str(_text(o, "Title")).is_equal("Victory")
	assert_str(_text(o, "Stats")).is_equal("Time 3:42, hull 64%")
	assert_str(_text(o, "Votes")).contains("0/2")
	assert_object(o.find_child("RunAgain", true, false)).is_null()
	(o.find_child("Vote", true, false) as Button).pressed.emit()
	var rec: StationFixture.RecordingClient = StationFixture.sent(o.ctx)
	assert_array(rec.of("run_again")[0][1]).is_equal([0, true])
	# Another player with the same name voted: still ours to cast (by session id).
	var votes: Dictionary = {"ship": 0, "voters": ["Ana"], "sessions": [99], "needed": 2}
	o.ctx.crew.handle_event({"type": "run_votes", "payload": votes}, 0)
	assert_str(_text(o, "Votes")).contains("1/2: Ana")
	assert_str((o.find_child("Vote", true, false) as Button).text).is_equal("Run again")
	votes["sessions"] = [StationFixture.SESSION]
	o.ctx.crew.handle_event({"type": "run_votes", "payload": votes}, 0)
	(o.find_child("Vote", true, false) as Button).pressed.emit()
	assert_array(rec.of("run_again")[1][1]).is_equal([0, false])
	o.ctx.crew.reset_run()
	assert_bool(o.visible).is_false()


# FT: FT-M1-012
# Every station shows the card; a viewer gets no vote, the host runs it again at once.
func test_viewer_sees_the_card_and_host_restarts() -> void:
	var v: OutcomeCard = _card("viewer")
	_over(v, "loss")
	assert_bool(v.visible).is_true()
	assert_str(_text(v, "Title")).is_equal("Ship lost")
	assert_object(v.find_child("Vote", true, false)).is_null()
	assert_object(v.find_child("RunAgain", true, false)).is_null()
	var h: OutcomeCard = _card("viewer", true)
	_over(h, "loss")
	(h.find_child("RunAgain", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(h.ctx).of("run_again")[0][1]).is_equal([0, true])


# FT: FT-M1-012
# C2: the card says why the run ended: the win rule, the ship destroyed, or the crew gave up.
func test_the_card_says_why_you_won_or_lost() -> void:
	var o: OutcomeCard = _card("tactical")
	_over(o, "win")
	assert_str(_text(o, "Why")).is_equal(tr("outcome.why_win"))
	var lost: Dictionary = {"ship": 0, "outcome": "loss", "time_s": 90.0, "hull": 0.0}
	o.ctx.crew.handle_event({"type": "ship_outcome", "payload": lost}, 0)
	assert_str(_text(o, "Why")).is_equal(tr("outcome.why_destroyed"))
	lost["hull"] = 0.4  # a loss with hull left: the crew gave up
	o.ctx.crew.handle_event({"type": "ship_outcome", "payload": lost}, 0)
	assert_str(_text(o, "Why")).is_equal(tr("outcome.why_gave_up"))


# FT: FT-M1-012
# C14: a captain or viewer gets no button but is told who starts the next run.
func test_a_viewer_is_told_who_runs_it_again() -> void:
	var v: OutcomeCard = _card("viewer")
	_over(v, "win")
	assert_str(_text(v, "Note")).is_equal(tr("outcome.watch"))
	var crew: OutcomeCard = _card("tactical")
	_over(crew, "win")
	assert_str(_text(crew, "Note")).is_empty()


# FT: FT-M1-012
# C14: the host's Run again waits for crew who haven't voted: the first tap names them, the
# second runs it anyway; with nobody left to wait for it runs at once.
func test_the_hosts_run_again_waits_for_the_crew_with_one_confirm() -> void:
	var h: OutcomeCard = _card("viewer", true)
	h.ctx.crew.lobby[0]["seats"] = [
		{"name": h.ctx.settings.player_name, "seat": "viewer"},
		{"name": "Bo", "seat": "tactical"},
		{"name": "Cy", "seat": "tactical"},
	]
	_over(h, "win")
	var rec: StationFixture.RecordingClient = StationFixture.sent(h.ctx)
	(h.find_child("RunAgain", true, false) as Button).pressed.emit()
	assert_array(rec.of("run_again")).is_empty()
	assert_str((h.find_child("RunAgain", true, false) as Button).text).contains("Bo, Cy")
	(h.find_child("RunAgain", true, false) as Button).pressed.emit()
	assert_array(rec.of("run_again")[0][1]).is_equal([0, true])
	# Everyone voted: one tap.
	var all: Dictionary = {"ship": 0, "voters": ["Bo", "Cy"], "sessions": [1, 2], "needed": 2}
	h.ctx.crew.handle_event({"type": "run_votes", "payload": all}, 0)
	(h.find_child("RunAgain", true, false) as Button).pressed.emit()
	assert_int(rec.of("run_again").size()).is_equal(2)


# FT: FT-M1-012
# Through the shell: the dev seat starts, the enemy is destroyed, the card shows
# Victory, its Run again button (1 of 1 crew) resets the run, the shell is back in the
# lobby, and Start brings the station screen up on the new world.
func test_shell_runs_again_after_a_win() -> void:
	var s: NetServer = _h.server(true)
	var c: NetClient = _h.client(s, "Ana")
	assert_bool(await _h.until(c.is_welcomed)).is_true()
	var shell: ClientShell = auto_free(ClientShell.new())
	shell.setup(c, ClientSettings.new(SETTINGS))
	add_child(shell)
	var crew: CrewState = shell.ctx.crew
	assert_bool(await _until(func() -> bool: return not crew.catalogue.is_empty())).is_true()
	shell.ctx.intents.pick(NetHarness.PLAYER, StationCatalogue.ALL)
	assert_bool(await _until(func() -> bool: return crew.lobby.has(NetHarness.PLAYER))).is_true()
	shell.ctx.intents.start()
	assert_bool(await _until(func() -> bool: return shell.screen != null)).is_true()
	var old_world: SimWorld = s.world
	var hit: SimHit = SimHit.new()
	hit.target_id = NetHarness.ENEMY
	DamageSystem.apply_hit(s.world, hit, 1.0e15)
	assert_bool(await _until(func() -> bool: return shell.outcome_card.visible)).is_true()
	assert_str((shell.outcome_card.find_child("Title", true, false) as Label).text).is_equal(
		"Victory"
	)
	var vote: Callable = func() -> bool:
		return (
			shell.outcome_card.find_child("Vote", true, false) != null
			and str(crew.ship_outcome.get(NetHarness.PLAYER, {}).get("needed", 0)) == "1"
		)
	assert_bool(await _until(vote)).is_true()
	(shell.outcome_card.find_child("Vote", true, false) as Button).pressed.emit()
	assert_bool(await _until(func() -> bool: return shell.lobby != null)).is_true()
	assert_object(s.world).is_not_same(old_world)
	assert_bool(shell.outcome_card.visible).is_false()
	shell.ctx.intents.start()
	assert_bool(await _until(func() -> bool: return shell.screen != null)).is_true()
	assert_bool(await _until(func() -> bool: return s.world.tick > 2)).is_true()


## Polls only the shell's own client (the shell takes its events). The all-stations
## screen builds in well under a second headless (docs/research/devseat-profile.md), so
## 15 s is room for a loaded machine, not a build time.
func _until(cond: Callable, timeout_ms: int = SLOW_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while not cond.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true
