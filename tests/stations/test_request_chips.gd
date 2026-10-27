extends GdUnitTestSuite
## Request chips on the station screens (StationPanel, ChipMenu, ChipStrip, §5.0, §7.4):
## B sends the station's chip or opens the numbered list, a joint view runs a request to
## its own station as a direct action, Hard switches chips off, and a received chip is
## answered with Enter or Backspace.

const SETTINGS: String = "user://test_request_chips.cfg"
const CHIPS: StationViews.Section = StationViews.Section.CHIPS


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String, code: String = "easy") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	ctx.crew.toggles = DataToggles.parse(code)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	return s


func _ev(id: String, s: StationScreen) -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, "kbm", s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": "kbm",
	}


func _sent(s: StationScreen, method: String) -> Array:
	return StationFixture.sent(s.ctx).of(method)


func _menu(s: StationScreen) -> ChipMenu:
	return s.focused_panel().find_children("*", "ChipMenu", true, false)[0] as ChipMenu


# FT: FT-STN-010, FT-PAIR-021
# A station with one chip sends it at once with B; with several, B opens a numbered list and
# a number sends that one. Helm's one chip is boost; Science's two are sensor power and the
# scan mark; Engineering sends none.
func test_b_sends_a_chip_or_opens_the_list() -> void:
	var helm: StationScreen = await _screen("helm")
	assert_bool(helm.dispatch(_ev("request", helm))).is_true()
	assert_array(_sent(helm, "send_chip")[0][1]).is_equal(["boost", -1])
	var science: StationScreen = await _screen("science")
	assert_bool(science.dispatch(_ev("request", science))).is_true()
	assert_array(_sent(science, "send_chip")).is_empty()
	var menu: ChipMenu = _menu(science)
	assert_bool(menu.visible).is_true()
	assert_str((menu.find_child("Chip1", true, false) as Button).text).contains("Power to sensors")
	assert_str((menu.find_child("Chip2", true, false) as Button).text).contains(
		"Fly to the scan mark"
	)
	assert_bool(menu.choose(1)).is_true()
	assert_array(_sent(science, "send_chip")[0][1]).is_equal(["scan_mark", -1])
	assert_bool(menu.visible).is_false()
	# B again closes an open list instead of sending.
	science.dispatch(_ev("request", science))
	science.dispatch(_ev("request", science))
	assert_bool(menu.visible).is_false()
	assert_int(_sent(science, "send_chip").size()).is_equal(1)
	var eng: StationScreen = await _screen("engineering")
	assert_bool(eng.dispatch(_ev("request", eng))).is_false()


# FT: FT-STN-010
# Weapons' list has power and "bring mount N to bear", which carries the selected mount.
func test_bring_to_bear_carries_the_selected_mount() -> void:
	var s: StationScreen = await _screen("weapons")
	var panel: WeaponsPanel = s.focused_panel() as WeaponsPanel
	panel.mount = 0
	if panel.mount_count() > 1:
		panel.mount = 1
	s.dispatch(_ev("request", s))
	var menu: ChipMenu = _menu(s)
	assert_str((menu.find_child("Chip2", true, false) as Button).text).contains(
		"Bring mount %d to bear" % (panel.mount + 1)
	)
	menu.choose(1)
	assert_array(_sent(s, "send_chip")[0][1]).is_equal(["bring_to_bear", panel.mount])


# FT: FT-PAIR-009, FT-PAIR-021, FT-PAIR-017
# Hard turns request chips off; an edited set with the toggle off does too.
func test_chips_are_off_on_hard_and_off_by_toggle() -> void:
	var hard: StationScreen = await _screen("helm", "hard")
	assert_bool(hard.dispatch(_ev("request", hard))).is_false()
	assert_array(_sent(hard, "send_chip")).is_empty()
	var custom: String = DataToggles.of_preset("easy").with_value(&"chips", 0).encode()
	var off: StationScreen = await _screen("weapons", custom)
	assert_bool(off.dispatch(_ev("request", off))).is_false()
	var comms: StationScreen = await _screen("comms", custom)
	assert_bool(comms.dispatch(_ev("request", comms))).is_false()


# FT: FT-JNT-005
# In a joint view the request to the other station runs as the direct action at any
# difficulty: Boost in Drive (Helm + Engineering) boosts at once; a probe from Logistics
# (Engineering + Relay) is fabricated; no chip is sent.
func test_a_joint_view_runs_its_own_requests_directly() -> void:
	for code: String in ["easy", "hard"]:
		var drive: StationScreen = await _screen("drive", code)
		drive.focus(drive.stations.find("helm"))
		assert_bool(drive.dispatch(_ev("request", drive))).is_true()
		assert_array(_sent(drive, "send_chip")).is_empty()
		assert_str(_sent(drive, "command")[-1][1][0]["kind"]).is_equal("boost")
	var logistics: StationScreen = await _screen("logistics", "hard")
	logistics.focus(logistics.stations.find("relay"))
	assert_bool(logistics.dispatch(_ev("request", logistics))).is_true()
	assert_str(_sent(logistics, "command")[-1][1][0]["kind"]).is_equal("fabricate_probe")
	assert_array(_sent(logistics, "send_chip")).is_empty()


func _put_chip(s: StationScreen, id: int, chip: String, from: String, to: String) -> void:
	var rows: Array = s.ctx.view.blocks.get(CHIPS, {}).get("chips", [])
	(
		rows
		. append(
			{
				"id": id,
				"chip": NetChips.index_of(chip),
				"arg": -1,
				"from": StationViews.CREW.find(from),
				"to": StationViews.CREW.find(to),
				"sent": s.ctx.view.tick - 360,
				"expires": s.ctx.view.tick + 840,
			}
		)
	)
	s.ctx.view.blocks[CHIPS] = {"chips": rows}


# FT: FT-PAIR-013, FT-PAIR-021
# A chip sent to this screen shows with its sender and time left, Enter answers the oldest
# (Backspace declines), and a chip this screen sent shows as waiting.
func test_a_received_chip_is_shown_and_answered() -> void:
	var s: StationScreen = await _screen("engineering")
	_put_chip(s, 5, "boost", "helm", "engineering")
	_put_chip(s, 6, "power", "weapons", "engineering")
	s._process(0.016)
	var strip: ChipStrip = s.chip_strip
	assert_bool(strip.visible).is_true()
	var texts: Array = strip.get_children().map(func(l: Label) -> String: return l.text)
	assert_str(texts[0]).is_equal("Helm asks: Boost · 14 s")
	assert_str(texts[1]).is_equal("Weapons asks: Power to weapons · 14 s")
	assert_str(texts[2]).is_equal("Enter accepts · Backspace declines")
	assert_bool(s.dispatch(_ev("accept", s))).is_true()
	assert_array(_sent(s, "answer_chip")[0][1]).is_equal([5, true])
	assert_bool(s.dispatch(_ev("decline", s))).is_true()
	assert_array(_sent(s, "answer_chip")[1][1]).is_equal([5, false])
	# With no chip open Enter does nothing.
	var helm: StationScreen = await _screen("helm")
	_put_chip(helm, 9, "boost", "helm", "engineering")
	helm._process(0.016)
	assert_bool(helm.dispatch(_ev("accept", helm))).is_false()
	var waiting: Label = helm.chip_strip.get_child(0)
	assert_str(waiting.text).is_equal("To Engineering: Boost · 14 s")
	I18n.apply("pt_PT")
	helm._process(0.016)
	assert_str((helm.chip_strip.get_child(0) as Label).text).is_equal(
		"Para Engenharia: Impulso · 14 s"
	)


# FT: FT-PAIR-013
# The strip shows what a time-out takes away: when the chip leaves the view, so does its line.
func test_an_expired_chip_leaves_the_strip_without_a_word() -> void:
	var s: StationScreen = await _screen("engineering")
	_put_chip(s, 5, "boost", "helm", "engineering")
	s._process(0.016)
	assert_bool(s.chip_strip.visible).is_true()
	s.ctx.view.blocks[CHIPS] = {"chips": []}
	s._process(0.016)
	assert_bool(s.chip_strip.visible).is_false()
	assert_int(s.chip_strip.get_child_count()).is_equal(0)
