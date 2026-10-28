extends GdUnitTestSuite
## The outcome card, the debrief and the M4 screens against the phone frame (#28 follow-up,
## design 2.9, 2.10, 2.13), in both orientations: the outcome card fills the safe area with
## Outcome and Debrief tabs; the floating votes (give up, relaunch) and the handover notice
## sit under the frame's view-top row; the pause and takeover sheet and the scoreboard keep
## their buttons at the bottom right above the gesture band; the main menu offers Full
## screen at the top right. Every tap target passes TapAudit.

const SETTINGS: String = "user://test_m4_phone_screens.cfg"
const CASES: Array = [
	[Vector2i(844, 390), [47, 0, 47, 21]],
	[Vector2i(390, 844), [0, 47, 0, 34]],
]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]
const Shot: GDScript = preload("res://tests/stations/m4_phone/m4_phone_shot.gd")


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	FullscreenButton.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A phone-sized viewport with a full-rect root in the phone theme.
func _root(case: Array) -> Control:
	SafeArea.simulate(case[1])
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = case[0]
	add_child(vp)
	var root: Control = Control.new()
	root.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(root)
	return root


## A four-ship fleet (Kestrel, Heron, Osprey, Merlin on teams A, B, A, B).
func _ctx(entry: String, mode: String) -> StationContext:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	StationFixture.fleet(ctx, mode, Shot.NAMES.slice(0, 4), [0, 1, 0, 1], true)
	return ctx


func _event(ctx: StationContext, type: String, p: Dictionary) -> void:
	ctx.crew.handle_event({"type": type, "payload": p}, StationFixture.NOW_MS)


## The station screen of the context's pick, as the client shell shows it.
func _station(root: Control, ctx: StationContext) -> StationScreen:
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	root.add_child(s)
	return s


## A shell overlay, centred as the client shell adds it.
func _centred(root: Control, c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(c)


func _frames(n: int = 6) -> void:
	for i: int in n:
		await get_tree().process_frame


func _clean(node: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(node)
	assert_array(report["targets"]).override_failure_message(what).is_not_empty()
	for k: String in AUDIT:
		(
			assert_array(report[k])
			. override_failure_message("%s %s: %s" % [what, k, report[k]])
			. is_empty()
		)


## The lowest top of a floating prompt: under the frame's view-top row.
func _under_row(s: StationScreen) -> float:
	return s.frame.view_top.get_global_rect().position.y + VotePrompt.VIEW_TOP_ROW


func _drop(root: Control) -> void:
	var vp: Node = root.get_parent()
	vp.remove_child(root)
	root.free()


# FT: FT-M1-012, FT-MIS-006
# On a phone the outcome card fills the safe area above the band, its Outcome and Debrief
# tabs switch the page, the debrief scrolls, and Run again (host) or Vote (crew) at the
# bottom right sends the run-again intent.
func test_outcome_card_fills_the_phone_with_two_tabs() -> void:
	for case: Array in CASES:
		for host: bool in [true, false]:
			var root: Control = _root(case)
			var ctx: StationContext = StationFixture.context("helm", SETTINGS)
			ctx.crew.host = host
			_station(root, ctx)
			var card: OutcomeCard = OutcomeCard.new()
			_centred(root, card)
			card.setup(ctx)
			_event(ctx, "run_over", {"ship": 0, "outcome": "win", "time_s": 412.0, "hull": 0.58})
			_event(ctx, "run_votes", {"ship": 0, "voters": ["Bo"], "needed": 2})
			_event(ctx, "debrief", Shot.debrief_record())
			await _frames()
			var what: String = "%s host %s" % [case[0], host]
			var tap: Rect2 = SafeArea.tap_rect(card)
			assert_vector(card.get_global_rect().position).is_equal(tap.position)
			assert_vector(card.get_global_rect().size).is_equal(tap.size)
			assert_object(card.find_child("OpenDebrief", true, false)).is_null()
			assert_int(card.tabs.tab_count()).is_equal(2)
			var outcome: Control = card.find_child("Outcome", true, false)
			var debrief: DebriefCard = card.find_child("Debrief", true, false)
			assert_bool(outcome.visible and not debrief.visible).is_true()
			_clean(card, what + " outcome")
			card.tabs.tab(1).pressed.emit()
			await _frames(2)
			assert_bool(debrief.visible and not outcome.visible).is_true()
			var scroll: ScrollContainer = (
				debrief.find_children("*", "ScrollContainer", true, false)[0]
			)
			assert_float(scroll.get_v_scroll_bar().max_value).is_greater(scroll.size.y)
			_clean(card, what + " debrief")
			var button: Button = card.find_child("RunAgain" if host else "Vote", true, false)
			assert_float(button.get_global_rect().end.x).is_greater(tap.end.x - 32.0)
			assert_float(button.get_global_rect().end.y).is_greater(tap.end.y - 32.0)
			button.pressed.emit()
			assert_array(StationFixture.sent(ctx).of("run_again")[-1][1]).is_equal([0, true])
			card.tabs.tab(0).pressed.emit()
			assert_bool(outcome.visible and not debrief.visible).is_true()
			_drop(root)


# FT: FT-M1-012
# A tablet or desktop keeps the centred card with its Open debrief button and no tabs.
func test_outcome_card_off_a_phone_keeps_the_button() -> void:
	var root: Control = _root([Vector2i(1280, 800), []])
	var ctx: StationContext = StationFixture.context("helm", SETTINGS)
	var card: OutcomeCard = OutcomeCard.new()
	_centred(root, card)
	card.setup(ctx)
	_event(ctx, "run_over", {"ship": 0, "outcome": "loss", "time_s": 60.0, "hull": 0.0})
	_event(ctx, "debrief", Shot.debrief_record())
	await _frames()
	assert_object(card.tabs).is_null()
	var open: Button = card.find_child("OpenDebrief", true, false)
	open.pressed.emit()
	assert_bool((card.find_child("Debrief", true, false) as Control).visible).is_true()
	_drop(root)


# FT: FT-MIS-016, FT-MIS-030
# The give-up vote over Helm (race) and the relaunch vote over a friendly ship's main screen
# float under the view-top row, inside the safe area and above the band.
func test_floating_votes_sit_under_the_view_top_row() -> void:
	for case: Array in CASES:
		for kind: VotePrompt.Kind in [VotePrompt.Kind.FORFEIT, VotePrompt.Kind.RELAUNCH]:
			var root: Control = _root(case)
			var forfeit: bool = kind == VotePrompt.Kind.FORFEIT
			var ctx: StationContext = _ctx("helm", "race" if forfeit else "holdout")
			if forfeit:
				_event(
					ctx,
					"abandon_votes",
					{"ship": 0, "voters": ["Bo"], "sessions": [9], "needed": 2}
				)
			else:
				_event(ctx, "picked", {"ship": 1, "entry": "viewer"})
				_event(ctx, "eliminated", FleetMessages.eliminated(0, "destroyed", 2))
				_event(ctx, "handover", FleetMessages.handover(0, 1))
			var s: StationScreen = _station(root, ctx)
			var p: VotePrompt = VotePrompt.new()
			root.add_child(p)
			p.setup(ctx, kind)
			await _frames()
			var what: String = "%s %s" % [case[0], p.name]
			assert_bool(p.visible).override_failure_message(what).is_true()
			var r: Rect2 = p.get_global_rect()
			assert_float(r.position.y).override_failure_message(what).is_greater_equal(
				_under_row(s)
			)
			assert_bool(SafeArea.tap_rect(p).encloses(r)).override_failure_message(what).is_true()
			_clean(p, what)
			_drop(root)


# FT: FT-MIS-030
# The handover notice sits under the view-top row with OK at its right; OK hides it.
func test_handover_notice_sits_under_the_row_with_ok_at_the_right() -> void:
	for case: Array in CASES:
		var root: Control = _root(case)
		var ctx: StationContext = _ctx("viewer", "teams")
		_event(ctx, "picked", {"ship": 1, "entry": "viewer"})
		_event(ctx, "eliminated", FleetMessages.eliminated(0, "destroyed", 0))
		_event(ctx, "handover", FleetMessages.handover(0, 1))
		var s: StationScreen = _station(root, ctx)
		var n: HandoverNotice = HandoverNotice.new()
		# As the client shell adds it.
		n.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		n.grow_horizontal = Control.GROW_DIRECTION_BOTH
		n.position.y += 64
		root.add_child(n)
		n.setup(ctx)
		await _frames()
		var r: Rect2 = n.get_global_rect()
		assert_float(r.position.y).is_greater_equal(_under_row(s))
		assert_bool(SafeArea.tap_rect(n).encloses(r)).is_true()
		var ok: Button = n.find_child("Ok", true, false)
		assert_float(ok.get_global_rect().get_center().x).is_greater(r.get_center().x)
		_clean(n, "%s handover" % case[0])
		ok.pressed.emit()
		assert_bool(n.visible).is_false()
		_drop(root)


# FT: FT-NET-034, FT-NET-042, FT-MIS-040
# The pause is a sheet between the top bar and the band, its buttons at the bottom right:
# the host's own paused ship (vote, abandon, resume) and an ally's takeover buttons.
func test_pause_and_takeover_sheet_keeps_buttons_bottom_right() -> void:
	for case: Array in CASES:
		for takeover: bool in [false, true]:
			var root: Control = _root(case)
			var ctx: StationContext = _ctx("helm", "teams")
			if takeover:
				_event(ctx, "picked", {"ship": 2, "entry": "helm"})
			else:
				ctx.crew.host = true
				_event(ctx, "pause", {"host": true})
				_event(
					ctx,
					"abandon_votes",
					{"ship": 0, "voters": ["Bo"], "sessions": [9], "needed": 2}
				)
			_event(ctx, "pause", {"ship": 0, "uncovered": ["science", "comms"]})
			var s: StationScreen = _station(root, ctx)
			var o: PauseOverlay = PauseOverlay.new()
			_centred(root, o)
			o.setup(ctx)
			await _frames()
			var what: String = "%s %s" % [case[0], "takeover" if takeover else "pause"]
			var tap: Rect2 = SafeArea.tap_rect(o)
			# The sheet spans the safe width down to the band, under the live top bar.
			var sr: Rect2 = o.get_global_rect()
			assert_float(sr.size.x).override_failure_message(what).is_equal(tap.size.x)
			assert_float(sr.end.y).override_failure_message(what).is_equal(tap.end.y)
			assert_float(sr.position.y).override_failure_message(what).is_equal(
				s.frame.view_top.get_global_rect().position.y
			)
			var buttons: Control = o.find_child("Buttons", true, false)
			assert_int(buttons.get_child_count()).is_equal(2 if takeover else 3)
			var last: Control = buttons.get_child(buttons.get_child_count() - 1)
			var lr: Rect2 = last.get_global_rect()
			assert_float(lr.end.x).override_failure_message(what).is_greater(tap.end.x - 32.0)
			assert_float(lr.end.y).override_failure_message(what).is_greater(tap.end.y - 32.0)
			_clean(o, what)
			if takeover:
				(o.find_child("Takeover_science", true, false) as Button).pressed.emit()
				assert_array(StationFixture.sent(ctx).of("takeover")[-1][1]).is_equal(
					[0, "science"]
				)
			_drop(root)


# FT: FT-MIS-030
# The scoreboard keeps Main menu at the bottom right above the band, with the relaunch vote
# beside it on its side and above it upright.
func test_scoreboard_main_menu_bottom_right() -> void:
	for case: Array in CASES:
		var root: Control = _root(case)
		var ctx: StationContext = _ctx("helm", "holdout")
		_event(ctx, "eliminated", FleetMessages.eliminated(0, "destroyed", 2))
		_event(ctx, "handover", FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD))
		var rows: Array = []
		for i: int in 4:
			rows.append(
				FleetMessages.scoreboard_row(i, Shot.NAMES[i], i % 2, "in_play", 2, 300.0, 0)
			)
		_event(ctx, "scoreboard", FleetMessages.scoreboard(rows))
		var s: ScoreboardScreen = ScoreboardScreen.new()
		s.setup(ctx)
		root.add_child(s)
		await _frames()
		var tap: Rect2 = SafeArea.tap_rect(s)
		var menu: Button = s.find_child("MainMenu", true, false)
		var mr: Rect2 = menu.get_global_rect()
		assert_float(mr.end.x).is_greater(tap.end.x - 32.0)
		assert_float(mr.end.y).is_greater(tap.end.y - 32.0)
		assert_float(mr.size.y).is_equal(float(UiTheme.TOUCH_PRIMARY))
		var vote: Button = s.relaunch.find_child("Relaunch", true, false)
		assert_bool(vote.is_visible_in_tree()).is_true()
		_clean(s, "%s scoreboard" % case[0])
		_drop(root)


# FT: FT-NET-013
# The main menu on a phone: Full screen (where the browser offers it) at the right of the
# title's row, and every target clean in both orientations.
func test_main_menu_offers_full_screen_beside_the_title() -> void:
	FullscreenButton.forced = 1
	for case: Array in CASES:
		var root: Control = _root(case)
		var m: MainMenu = MainMenu.new()
		m.web = true
		m.token_path = "user://test_m4_phone_none.token"
		m.pid_path = "user://test_m4_phone_none.pid"
		m.settings = ClientSettings.new(SETTINGS)
		root.add_child(m)
		await _frames()
		var fs: Button = m.find_child("Fullscreen", true, false)
		assert_bool(fs.is_visible_in_tree()).is_true()
		# Its whole label shows ("Full screen", not trimmed to the 48 px square).
		var font: Font = fs.get_theme_font("font")
		var text_w: float = (
			font
			. get_string_size(
				fs.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs.get_theme_font_size("font_size")
			)
			. x
		)
		assert_float(fs.size.x).is_greater(text_w)
		var tap: Rect2 = SafeArea.tap_rect(m)
		var fr: Rect2 = fs.get_global_rect()
		assert_float(fr.position.y).is_less(tap.position.y + 32.0)
		# At the right end of the title's row (the left column on its side).
		var row: Control = m.find_child("TitleRow", true, false)
		assert_float(fr.end.x).is_equal_approx(row.get_global_rect().end.x, 0.5)
		_clean(m, "%s menu" % case[0])
		_drop(root)
