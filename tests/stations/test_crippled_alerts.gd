extends GdUnitTestSuite
## Fail-forward and economy alerts (gp-09, gp-11): a crippled ship's countdown is the critical
## banner on Helm and the Captain, counting down until it limps home or the encounter ends;
## bounties and salvage are toasts on Comms and the Captain.

const SHIP: int = StationFixture.SHIP


func before_test() -> void:
	I18n.apply("en")
	AlertTones.sounds_dir = MainMenu.ALERT_SOUNDS


func _screen(seat: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(seat)
	var s: StationScreen = auto_free(StationScreen.new())
	s.panel_factory = func(_st: String) -> StationPanel: return StationPanel.new()
	s.setup(ctx)
	add_child(s)
	return s


func _event(s: StationScreen, type: String, payload: Dictionary) -> void:
	var p: Dictionary = {
		"ship": SHIP, "faction": 0, "other": -1, "value": 0.0, "vector": Vector3.ZERO, "tag": ""
	}
	p.merge(payload, true)
	s.ctx.crew.handle_event({"type": type, "payload": p}, s.ctx.now_ms())


func _advance(s: StationScreen, ms: int) -> void:
	StationFixture.clock(s.ctx).ms += ms
	s.critical.update(s.ctx.now_ms())


# FT: FT-MIS-050
func test_the_crippled_countdown_shows_on_helm_and_captain_until_docked() -> void:
	for seat: String in ["helm", "captain"]:
		var s: StationScreen = _screen(seat)
		_event(s, "crippled", {"value": 120.0})
		assert_str(s.critical.shown()).is_equal("Crippled: dock within 2:00 to limp home")
		assert_array(s.alerts.tones.played).is_equal([&"alert_red"])
		_advance(s, 30_500)
		assert_str(s.critical.shown()).is_equal("Crippled: dock within 1:30 to limp home")
		# A newer critical alert shows over it for a while, then the countdown is back.
		_event(s, "hull_critical", {})
		assert_str(s.critical.shown()).is_equal("Hull critical")
		_advance(s, CriticalBanner.SHOW_MS)
		assert_str(s.critical.shown()).starts_with("Crippled: dock within 1:2")
		_event(s, "limped_home", {})
		_advance(s, 100)
		assert_str(s.critical.shown()).is_empty()
		assert_array(s.toasts.texts()).is_equal(["Limped home: half pay"])
	var weapons: StationScreen = _screen("weapons")
	_event(weapons, "crippled", {"value": 120.0})
	assert_str(weapons.critical.shown()).is_empty()


# FT: FT-MIS-050
func test_the_countdown_runs_out_or_ends_with_the_encounter() -> void:
	var s: StationScreen = _screen("helm")
	_event(s, "crippled", {"value": 120.0})
	_advance(s, 120_000)
	assert_str(s.critical.shown()).is_empty()
	_event(s, "crippled", {"value": 120.0})
	_event(s, "encounter_end", {"ship": 1})
	_advance(s, 100)
	assert_str(s.critical.shown()).is_empty()


# FT: FT-MIS-052
func test_bounty_and_salvage_are_toasts_on_comms_and_captain() -> void:
	for seat: String in ["comms", "captain"]:
		var s: StationScreen = _screen(seat)
		_event(s, "bounty", {"value": 100.0})
		_event(s, "salvage", {"value": 150.0})
		assert_array(s.toasts.texts()).contains_exactly_in_any_order(
			["Bounty +100", "Salvage +150"]
		)
	var helm: StationScreen = _screen("helm")
	_event(helm, "bounty", {"value": 100.0})
	assert_array(helm.toasts.texts()).is_empty()
