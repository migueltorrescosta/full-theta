extends GdUnitTestSuite
## PauseOverlay: the host pause and the menu's Pause control (FT-MIS-040), the coverage pause's
## give-up toggle, the host's End now and takeover (FT-NET-041, FT-NET-042, #37 C11).

const HOST_PAUSE: Dictionary = {"host": true, "ship": -1, "uncovered": [], "crew": 0}
const COVERAGE_PAUSE: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}


func before() -> void:
	I18n.apply("en")


func _heading(o: PauseOverlay) -> String:
	return ((o.get_child(0) as VBoxContainer).get_child(0) as Label).text


func _overlay(host: bool) -> Array:
	var ctx: StationContext = StationFixture.context("tactical")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	ctx.crew.host = host
	return [ctx, o]


# FT: FT-MIS-040
func test_host_pause_text_and_resume_only_on_the_host() -> void:
	for host: bool in [true, false]:
		var made: Array = _overlay(host)
		var ctx: StationContext = made[0]
		var o: PauseOverlay = made[1]
		assert_bool(o.visible).is_false()
		ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
		assert_bool(o.visible).is_true()
		assert_bool(ctx.crew.paused.is_empty()).is_true()
		assert_str(_heading(o)).is_equal(TranslationServer.translate("pause.host"))
		assert_object(o.find_child("Abandon", true, false)).is_null()
		assert_object(o.find_child("Vote", true, false)).is_null()
		var resume: Button = o.find_child("Resume", true, false)
		assert_bool(resume != null).is_equal(host)
		assert_bool(o.find_child("EndNow", true, false) != null).is_equal(host)
		if host:
			resume.pressed.emit()
			var rec: StationFixture.RecordingClient = StationFixture.sent(ctx)
			assert_array(rec.of("host_pause")[0][1]).is_equal([false])
		ctx.crew.handle_event({"type": "resume", "payload": {"tick": 1, "host": true}}, 0)
		assert_bool(o.visible).is_false()


# FT: FT-MIS-040
# A host resume leaves a coverage pause (and its votes) in place.
func test_host_resume_keeps_the_coverage_pause() -> void:
	var made: Array = _overlay(true)
	var ctx: StationContext = made[0]
	var o: PauseOverlay = made[1]
	ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
	assert_object(o.find_child("Resume", true, false)).is_not_null()
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 1, "host": true}}, 0)
	assert_bool(ctx.crew.paused.has(0)).is_true()
	assert_bool(o.visible).is_true()
	assert_object(o.find_child("Resume", true, false)).is_null()


# FT: FT-MIS-040
# H1: each resume clears only the pause it names, in either order, and the host's Resume
# button works after a coverage pause lifted under a host pause.
func test_each_resume_clears_only_its_own_pause() -> void:
	var made: Array = _overlay(true)
	var ctx: StationContext = made[0]
	var o: PauseOverlay = made[1]
	ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
	ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 1, "host": false}}, 0)
	assert_bool(ctx.crew.paused.is_empty()).is_true()
	assert_bool(ctx.crew.host_paused).is_true()
	assert_bool(o.visible).is_true()
	var resume: Button = o.find_child("Resume", true, false)
	resume.pressed.emit()
	assert_array(StationFixture.sent(ctx).of("host_pause")[0][1]).is_equal([false])
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 2, "host": true}}, 0)
	assert_bool(o.visible).is_false()
	ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	ctx.crew.handle_event({"type": "pause", "payload": HOST_PAUSE}, 0)
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 3, "host": true}}, 0)
	assert_bool(ctx.crew.host_paused).is_false()
	assert_bool(o.visible).is_true()
	ctx.crew.handle_event({"type": "resume", "payload": {"tick": 4, "host": false}}, 0)
	assert_bool(o.visible).is_false()


# FT: FT-MIS-040
# The menu offers Pause to the co-op host only: not to a guest, not in PvP.
func test_pause_control_is_host_and_coop_only() -> void:
	var ctx: StationContext = StationFixture.context("tactical")
	var coop: Dictionary = {"ships": [{"id": 0, "faction": 0}, {"id": 1, "faction": 0}]}
	var pvp: Dictionary = {"ships": [{"id": 0, "faction": 0}, {"id": 1, "faction": 1}]}
	ctx.crew.catalogue = coop
	ctx.crew.host = true
	assert_bool(ctx.crew.can_host_pause()).is_true()
	ctx.crew.host = false
	assert_bool(ctx.crew.can_host_pause()).is_false()
	ctx.crew.host = true
	ctx.crew.catalogue = pvp
	assert_bool(ctx.crew.can_host_pause()).is_false()
	var menu: SettingsScreen = auto_free(SettingsScreen.new())
	menu.setup(ClientSettings.new("user://test_pause_overlay.cfg"), true)
	add_child(menu)
	var button: Button = menu.find_child("HostPause", true, false)
	assert_bool(button.visible).is_false()
	menu.set_pause_control(true)
	assert_bool(button.visible).is_true()
	var fired: Array[bool] = [false]
	menu.host_pause_requested.connect(func() -> void: fired[0] = true)
	button.pressed.emit()
	assert_bool(fired[0]).is_true()
	menu.set_pause_control(false)
	# In place: the same button, hidden (load fix 2).
	assert_object(menu.find_child("HostPause", true, false)).is_same(button)
	assert_bool(button.visible).is_false()


# FT: FT-NET-041
# #37 C11: one "Give up (n/needed)" toggle casts or withdraws the crew's vote and shows the
# count; the host's End now asks "End the game?" and then ends the game for everyone
# (`end_requested`, D353). A player never sees End now.
func test_pause_overlay_give_up_toggle_and_host_end_now() -> void:
	var made: Array = _overlay(true)
	var ctx: StationContext = made[0]
	var o: PauseOverlay = made[1]
	assert_bool(o.visible).is_false()
	ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	assert_bool(o.visible).is_true()
	# Crew changes it doesn't show leave its buttons alone.
	var vote: Button = o.find_child("Vote", true, false)
	ctx.crew.changed.emit(&"alert")
	ctx.crew.changed.emit(&"marks")
	assert_object(o.find_child("Vote", true, false)).is_same(vote)
	assert_str(vote.text).is_equal("Give up (0/0)")
	assert_bool(vote.toggle_mode).is_true()
	assert_object(o.find_child("Votes", true, false)).is_null()
	assert_object(o.find_child("Abandon", true, false)).is_null()
	vote.pressed.emit()
	var rec: StationFixture.RecordingClient = StationFixture.sent(ctx)
	assert_array(rec.of("vote_abandon")[0][1]).is_equal([0, true])
	var votes: Dictionary = {
		"ship": 0, "voters": ["Ana"], "sessions": [StationFixture.SESSION], "needed": 2
	}
	ctx.crew.handle_event({"type": "abandon_votes", "payload": votes}, 0)
	vote = o.find_child("Vote", true, false)
	assert_str(vote.text).is_equal("✓ Give up (1/2)")
	assert_bool(vote.button_pressed).is_true()
	vote.pressed.emit()
	assert_array(rec.of("vote_abandon")[1][1]).is_equal([0, false])
	var ended: Array[int] = [0]
	o.end_requested.connect(func() -> void: ended[0] += 1)
	(o.find_child("EndNow", true, false) as Button).pressed.emit()
	var dialog: ConfirmationDialog = o.find_child("EndDialog", true, false)
	assert_bool(dialog.visible).is_true()
	assert_str(dialog.dialog_text).is_equal("This ends the game for everyone in it.")
	assert_int(ended[0]).is_equal(0)
	dialog.confirmed.emit()
	assert_int(ended[0]).is_equal(1)
	assert_array(rec.of("abandon")).is_empty()
	var player: Array = _overlay(false)
	(player[0] as StationContext).crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	assert_object((player[1] as PauseOverlay).find_child("EndNow", true, false)).is_null()
	assert_object((player[1] as PauseOverlay).find_child("Vote", true, false)).is_not_null()


# FT: FT-NET-042
func test_viewers_of_a_paused_ship_may_take_over() -> void:
	var ctx: StationContext = StationFixture.context("viewer")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
	assert_object(o.find_child("Vote", true, false)).is_null()
	(o.find_child("Takeover_relay", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("takeover")[0][1]).is_equal([0, "relay"])


# FT: FT-NET-041
# Every label and button the overlay shows is translated, in co-op and PvP, before and after
# a vote, in each locale (a removed key showed "pause.vote" on the vote button).
func test_every_pause_text_is_translated() -> void:
	var coop: Array = [{"id": 0, "faction": 0}, {"id": 1, "faction": 0}]
	var pvp: Array = [{"id": 0, "faction": 0}, {"id": 1, "faction": 1}]
	for locale: String in I18n.LANGUAGES:
		I18n.apply(locale)
		for ships: Array in [coop, pvp]:
			for voted: bool in [false, true]:
				var made: Array = _overlay(true)
				var ctx: StationContext = made[0]
				var o: PauseOverlay = made[1]
				ctx.crew.catalogue = ctx.crew.catalogue.duplicate()
				ctx.crew.catalogue["ships"] = ships
				assert_bool(ctx.crew.is_pvp()).is_equal(ships == pvp)
				ctx.crew.handle_event({"type": "pause", "payload": COVERAGE_PAUSE}, 0)
				var sessions: Array = [StationFixture.SESSION] if voted else []
				var votes: Dictionary = {
					"ship": 0, "voters": ["Ana"], "sessions": sessions, "needed": 2
				}
				ctx.crew.handle_event({"type": "abandon_votes", "payload": votes}, 0)
				assert_object(o.find_child("Vote", true, false)).is_not_null()
				for node: Node in o.find_children("*", "", true, false):
					var text: String = ""
					if node is Button:
						text = (node as Button).text
					elif node is Label:
						text = (node as Label).text
					(
						assert_str(text)
						. override_failure_message("%s %s: raw key %s" % [locale, node.name, text])
						. not_contains("pause.")
					)
	I18n.apply("en")
