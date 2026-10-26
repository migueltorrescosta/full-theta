extends GdUnitTestSuite
## Weapons' reticle shows the contract flags (P9, FT-MIS-042): a contact a contract marks
## "disable, do not destroy" or "protect" carries the word on its chip and, selected, a line;
## with the flags not shared (no rows in the FEEDS block) the reticle shows none.

const SETTINGS: String = "user://test_weapons_flags.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(flags: Array) -> StationScreen:
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	ctx.view.blocks[StationViews.Section.FEEDS] = {
		"weak": [], "windows": [], "tracks": [], "flags": flags
	}
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _chips(panel: WeaponsPanel) -> Dictionary:
	var out: Dictionary = {}
	for it: Dictionary in panel.ctx.picture().items:
		if it["kind"] == "contact":
			out[int(it["id"])] = panel.target_chip(it)
	return out


# FT: FT-MIS-042
# Each flagged contact's chip names its flag; unflagged contacts keep the plain chip.
func test_flagged_contacts_show_their_flag() -> void:
	var s: StationScreen = await _screen(
		[
			{"contact": StationFixture.H2, "flag": 1},
			{"contact": StationFixture.F4, "flag": 2},
		]
	)
	var panel: WeaponsPanel = s.focused_panel() as WeaponsPanel
	assert_int(panel.contract_flag(StationFixture.H2)).is_equal(1)
	assert_int(panel.contract_flag(StationFixture.F4)).is_equal(2)
	assert_int(panel.contract_flag(StationFixture.U3)).is_equal(0)
	var chips: Dictionary = _chips(panel)
	assert_str(chips[StationFixture.H2]).ends_with("[disable]")
	assert_str(chips[StationFixture.F4]).ends_with("[protect]")
	assert_str(chips[StationFixture.U3]).not_contains("[")
	# Selected, the contract is spelled out among the feed lines.
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_array(panel.feed_lines()).contains(["Contract: disable, do not destroy"])
	s.ctx.crew.select("contact", StationFixture.F4)
	assert_array(panel.feed_lines()).contains(["Contract: protect"])


# FT: FT-MIS-042, FT-PAIR-007
# Without flag rows (the toggle off, nobody at Comms on the screen) the reticle shows no flag.
func test_no_rows_no_flags() -> void:
	var s: StationScreen = await _screen([])
	var panel: WeaponsPanel = s.focused_panel() as WeaponsPanel
	for chip: String in _chips(panel).values():
		assert_str(chip).not_contains("[")
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_array(panel.feed_lines()).is_empty()
