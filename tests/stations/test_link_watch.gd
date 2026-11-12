extends GdUnitTestSuite
## LinkWatch and JoinAdvice (C1, C12 client half; R24-1, R24-3, R11-2): the shell retries a
## dropped connection every 2 s for 20 s, then gives up; a rejection never retries; a close
## by a takeover (4001) never retries and offers Take back; every reject code has advice.


func _client(state: NetClient.State, code: int = -1) -> NetClient:
	var c: NetClient = NetClient.new()
	c.state = state
	c.close_code = code
	return c


# FT: FT-NET-025
# A dropped connection is retried at once, then every RESUME_MS, and given up on after
# GIVE_UP_MS; a welcomed client is fine again.
func test_a_dropped_connection_retries_then_gives_up() -> void:
	var w: LinkWatch = LinkWatch.new()
	var c: NetClient = _client(NetClient.State.CLOSED)
	assert_bool(w.update(c, 1000)).is_true()
	assert_int(w.status).is_equal(LinkWatch.Status.RETRYING)
	assert_bool(w.update(c, 1500)).is_false()
	assert_bool(w.update(c, 3000)).is_true()
	assert_bool(w.update(c, 1000 + LinkWatch.GIVE_UP_MS - 1)).is_true()
	assert_int(w.status).is_equal(LinkWatch.Status.RETRYING)
	assert_bool(w.update(c, 1000 + LinkWatch.GIVE_UP_MS)).is_false()
	assert_int(w.status).is_equal(LinkWatch.Status.GAVE_UP)
	# (no more retries until the player asks)
	assert_bool(w.update(c, 1000 + 2 * LinkWatch.GIVE_UP_MS)).is_false()
	w.restart(100_000)
	assert_int(w.status).is_equal(LinkWatch.Status.RETRYING)
	c.state = NetClient.State.WELCOMED
	assert_bool(w.update(c, 101_000)).is_false()
	assert_int(w.status).is_equal(LinkWatch.Status.OK)


# FT: FT-NET-025
# A rejected resume is final: no retry, and the status says so.
func test_a_rejection_never_retries() -> void:
	var w: LinkWatch = LinkWatch.new()
	var c: NetClient = _client(NetClient.State.REJECTED)
	assert_bool(w.update(c, 0)).is_false()
	assert_int(w.status).is_equal(LinkWatch.Status.REJECTED)


# FT: FT-NET-025, FT-NET-026
# R11-2: close code 4001 (another window took the session) stops the retries for good, so two
# windows sharing a token don't swap the session every 2 s.
func test_a_takeover_stops_the_retries() -> void:
	var w: LinkWatch = LinkWatch.new()
	var c: NetClient = _client(NetClient.State.CLOSED, NetTransport.CLOSE_TAKEN_OVER)
	assert_bool(w.update(c, 0)).is_false()
	assert_int(w.status).is_equal(LinkWatch.Status.TAKEN_OVER)
	assert_bool(w.update(c, 10_000)).is_false()
	assert_int(w.status).is_equal(LinkWatch.Status.TAKEN_OVER)
	# Take back: the clock starts over.
	w.restart(10_000)
	c.close_code = -1
	assert_int(w.status).is_equal(LinkWatch.Status.RETRYING)


# FT: FT-NET-013
# R24-1: each reject code, and a socket that closed with no answer, has plain advice.
func test_every_failure_has_advice() -> void:
	I18n.apply("en")
	for reason: String in [
		NetProtocol.REJECT_FULL, NetProtocol.REJECT_VERSION, NetProtocol.REJECT_BAD_HELLO, ""
	]:
		var text: String = JoinAdvice.for_failure(reason, "ws://192.168.1.20:47801")
		assert_str(text).override_failure_message(reason).is_not_empty()
		assert_str(text).override_failure_message(reason).not_contains("join.")
		assert_str(text).override_failure_message(reason).not_contains("_")
	assert_str(JoinAdvice.for_failure("", "ws://192.168.1.20:47801")).contains("192.168.1.20")
	assert_str(JoinAdvice.for_failure(NetProtocol.REJECT_FULL, "")).contains("full")
	assert_str(JoinAdvice.gone()).contains("host")


# FT: FT-STN-001
# C2: the top bar's goal chip is the first open objective with its progress, a short count for
# a phone, the survive line when none is open, and nothing before a snapshot or after an outcome.
func test_the_goal_chip_shows_the_objective_and_its_progress() -> void:
	I18n.apply("en")
	var open: Dictionary = {
		"subsystems": [],
		"objectives": [{"kind": StationCatalogue.OBJECTIVE_DESTROY_HOSTILES, "left": 3}]
	}
	assert_str(StatusView.goal_text(open, {})).is_equal("Goal: stop the hostiles (3 left)")
	assert_str(StatusView.goal_short(open, {})).is_equal("3 foes")
	var none: Dictionary = {"subsystems": [], "objectives": []}
	assert_str(StatusView.goal_text(none, {})).is_equal("Goal: survive until the run ends")
	assert_str(StatusView.goal_short(none, {})).is_empty()
	assert_str(StatusView.goal_text({}, {})).is_empty()
	assert_str(StatusView.goal_text(open, {"outcome": 1})).is_empty()
	assert_str(StatusView.goal_short(open, {"outcome": 1})).is_empty()
	var bar: TopBar = auto_free(TopBar.new())
	add_child(bar)
	bar.show_goal("Goal: x", "3 foes")
	assert_str((bar.find_child("Goal", true, false) as Label).text).is_equal("Goal: x")
	assert_float(bar.goal_height()).is_equal(TopBar.GOAL_H)
	bar.apply(LayoutMode.Form.PHONE_LANDSCAPE, false)
	assert_float(bar.goal_height()).is_equal(0.0)
