extends GdUnitTestSuite
## LobbyScreen, PauseOverlay and PlaceholderPanel.


func before() -> void:
	I18n.apply("en")


func _lobby(entry: String) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context(entry)
	ctx.crew.lobby[0]["started"] = false
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _row(l: LobbyScreen, id: String) -> Control:
	return l.find_child("Entry_" + id, true, false)


# FT: FT-STN-015, FT-JNT-006, FT-M1-018, FT-M1-005
func test_catalogue_shows_load_tags_and_joint_hints() -> void:
	var l: LobbyScreen = _lobby("helm")
	var tags: Dictionary = {
		"helm": "intense",
		"weapons": "intense",
		"engineering": "busy",
		"science": "busy",
		"relay": "light",
		"comms": "light",
		"tactical": "intense",
		"systems": "busy",
		"ops": "light",
		"captain": "light",
	}
	for id: String in tags:
		var tag: Label = _row(l, id).get_node("LoadTag")
		assert_str(tag.text).is_equal(tr("load." + tags[id]))
	assert_str((_row(l, "viewer").get_node("LoadTag") as Label).text).is_empty()
	var hint: Label = _row(l, "systems").get_node("Hint")
	assert_str(hint.text).is_equal("Plays Engineering and Science solo.")
	assert_str((_row(l, "helm").get_node("Hint") as Label).text).is_empty()
	# Science and Comms are pickable (placeholders, FT-M1-005).
	(_row(l, "science").get_child(0) as Button).pressed.emit()
	assert_array(StationFixture.sent(l.ctx).of("pick")[0][1]).is_equal([0, "science"])


# FT: FT-NET-019
func test_start_is_for_crew_of_a_covered_ship() -> void:
	var l: LobbyScreen = _lobby("ops")
	var start: Button = l.find_child("Start", true, false)
	assert_bool(start.disabled).is_false()
	start.pressed.emit()
	assert_array(StationFixture.sent(l.ctx).of("set_ready")[0][1]).is_equal([true])
	l.ctx.crew.lobby[0]["ready"] = false
	l.ctx.crew.lobby[0]["uncovered"] = ["comms"]
	l.refresh()
	assert_bool(start.disabled).is_true()
	assert_str((l.find_child("Coverage", true, false) as Label).text).contains("Comms")
	assert_bool((_lobby("viewer").find_child("Start", true, false) as Button).disabled).is_true()


# FT: FT-NET-041
func test_pause_overlay_vote_and_host_abandon() -> void:
	var ctx: StationContext = StationFixture.context("tactical")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	assert_bool(o.visible).is_false()
	ctx.crew.host = true
	var pause: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}
	ctx.crew.handle_event({"type": "pause", "payload": pause}, 0)
	assert_bool(o.visible).is_true()
	# Crew changes it doesn't show leave its buttons alone.
	var vote: Button = o.find_child("Vote", true, false)
	ctx.crew.changed.emit(&"alert")
	ctx.crew.changed.emit(&"marks")
	assert_object(o.find_child("Vote", true, false)).is_same(vote)
	vote.pressed.emit()
	(o.find_child("Abandon", true, false) as Button).pressed.emit()
	var rec: StationFixture.RecordingClient = StationFixture.sent(ctx)
	assert_array(rec.of("vote_abandon")[0][1]).is_equal([0, true])
	assert_array(rec.of("abandon")[0][1]).is_equal([0])
	var votes: Dictionary = {
		"ship": 0, "voters": ["Ana"], "sessions": [StationFixture.SESSION], "needed": 2
	}
	ctx.crew.handle_event({"type": "abandon_votes", "payload": votes}, 0)
	(o.find_child("Vote", true, false) as Button).pressed.emit()
	assert_array(rec.of("vote_abandon")[1][1]).is_equal([0, false])
	assert_str((o.find_child("Votes", true, false) as Label).text).contains("1/2")


# FT: FT-NET-042
func test_viewers_of_a_paused_ship_may_take_over() -> void:
	var ctx: StationContext = StationFixture.context("viewer")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	var pause: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}
	ctx.crew.handle_event({"type": "pause", "payload": pause}, 0)
	assert_object(o.find_child("Vote", true, false)).is_null()
	(o.find_child("Takeover_relay", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("takeover")[0][1]).is_equal([0, "relay"])


# FT: FT-M1-005
func test_placeholder_reads_out_its_station_def() -> void:
	var ctx: StationContext = StationFixture.context("comms")
	var p: PlaceholderPanel = auto_free(StationRegistry.make("comms") as PlaceholderPanel)
	assert_object(p).is_not_null()
	p.setup(ctx, "comms")
	add_child(p)
	var text: String = (p.get_child(0).get_child(1) as Label).text
	assert_str(text).contains("kin").contains("status").contains("contacts")
	assert_str((p.get_child(0).get_child(0) as Label).text).is_equal("Comms")
