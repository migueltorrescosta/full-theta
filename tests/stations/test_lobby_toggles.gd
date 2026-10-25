extends GdUnitTestSuite
## The lobby's data-shortcut section (LobbyScreen, FT-STN-016, FT-PAIR-017): Easy on a first
## launch and persisted per host, the toggles behind "Customise" with a one-line description
## naming both stations, the "<Preset> (custom)" name, and the lock at Start.

const PATH: String = "user://test_lobby_toggles.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")
	DirAccess.remove_absolute(PATH)


func _lobby(host: bool = true, started: bool = false) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("helm", PATH)
	ctx.crew.host = host
	ctx.crew.lobby[0]["started"] = started
	ctx.crew.started.erase(0)
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _row(l: LobbyScreen, id: String) -> Control:
	return l.find_child("Toggle_" + id, true, false)


func _lobby_event(l: LobbyScreen, code: String, started: bool = false) -> void:
	var state: Dictionary = l.ctx.crew.lobby[0].duplicate()
	state["toggles"] = code
	state["started"] = started
	l.ctx.crew.handle_event({"type": "lobby", "payload": state}, 0)


func _sent(l: LobbyScreen) -> Array:
	return StationFixture.sent(l.ctx).of("set_toggles")


# FT: FT-STN-016
# A first launch is Easy; the host's choice is saved with its settings and comes back, and a
# damaged value in the file is Easy again.
func test_the_lobby_defaults_to_easy_and_remembers_the_host() -> void:
	var fresh: ClientSettings = ClientSettings.new(PATH)
	assert_str(fresh.host_toggles).is_equal("easy")
	assert_int(fresh.load_file()).is_equal(OK)
	assert_str(fresh.host_toggles).is_equal("easy")
	var l: LobbyScreen = _lobby()
	assert_str((l.find_child("PresetName", true, false) as Label).text).is_equal("Easy")
	assert_str((l.find_child("DifficultyLine", true, false) as Label).text).is_equal(
		"Difficulty: Easy"
	)
	(l.find_child("Preset_hard", true, false) as Button).pressed.emit()
	assert_array(_sent(l)[-1][1]).is_equal(["hard"])
	var reloaded: ClientSettings = ClientSettings.new(PATH)
	reloaded.load_file()
	assert_str(reloaded.host_toggles).is_equal("hard")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("lobby", "toggles", "extreme")
	cfg.save(PATH)
	reloaded.load_file()
	assert_str(reloaded.host_toggles).is_equal("easy")


# FT: FT-STN-016
# The host's lobby sends the saved set once when the server's lobby state arrives; a set
# the server already has is not sent; a guest never sends.
func test_the_host_lobby_pushes_its_saved_set_once() -> void:
	var l: LobbyScreen = _lobby()
	l.ctx.settings.host_toggles = "normal"
	_lobby_event(l, "easy")
	assert_array(_sent(l)).is_equal([["set_toggles", ["normal"]]])
	_lobby_event(l, "normal")
	_lobby_event(l, "normal")
	assert_int(_sent(l).size()).is_equal(1)
	var same: LobbyScreen = _lobby()
	same.ctx.settings.host_toggles = "easy"
	_lobby_event(same, "easy")
	assert_array(_sent(same)).is_empty()
	var guest: LobbyScreen = _lobby(false)
	guest.ctx.settings.host_toggles = "hard"
	_lobby_event(guest, "easy")
	assert_array(_sent(guest)).is_empty()


# FT: FT-STN-016, FT-PAIR-017
# The toggles sit behind "Customise", each with a one-line description that names both
# stations, in every language; the two Comms toggles say they arrive in M3 (D190).
func test_each_toggle_has_a_description_naming_both_stations() -> void:
	var l: LobbyScreen = _lobby()
	var rows: Control = l.find_child("Toggles", true, false)
	var dialog: Window = l.find_child("DifficultyDialog", true, false)
	assert_bool(dialog.visible).is_false()
	(l.find_child("Customise", true, false) as Button).pressed.emit()
	assert_bool(dialog.visible).is_true()
	dialog.hide()
	assert_int(rows.get_child_count()).is_equal(DataToggles.def().toggles.size())
	for lang: String in ["en", "pt_PT", "it"]:
		I18n.apply(lang)
		for t: DataToggleDef in DataToggles.def().toggles:
			var desc: String = (_row(l, String(t.id)).get_node("Desc") as Label).text
			assert_str(desc).override_failure_message("%s %s" % [lang, t.id]).is_not_empty()
			assert_bool(desc.contains("\n")).is_false()
			var named: int = 0
			for station: String in StationViews.CREW:
				if desc.contains(tr("station." + station)):
					named += 1
			(
				assert_int(named)
				. override_failure_message("%s %s: %s" % [lang, t.id, desc])
				. is_greater_equal(2)
			)
			if t.source != &"":
				assert_str(desc).contains(tr("station." + String(t.source)))
				assert_str(desc).contains(tr("station." + String(t.target)))
	I18n.apply("en")
	for id: String in ["contract_flags", "verify_chip"]:
		assert_str((_row(l, id).get_node("Line/Name") as Label).text).contains("arrives in M3")
	assert_bool((_row(l, "routes").get_node("Line/Name") as Label).text.contains("M3")).is_false()


# FT: FT-PAIR-017
# Changing one toggle sends the edited set and the lobby then names it "<Preset> (custom)";
# another preset replaces the edits.
func test_an_edited_set_is_named_custom() -> void:
	var l: LobbyScreen = _lobby()
	_lobby_event(l, "normal")
	assert_str((l.find_child("PresetName", true, false) as Label).text).is_equal("Normal")
	var pressed: Button = l.find_child("Preset_normal", true, false)
	assert_bool(pressed.button_pressed).is_true()
	var weak: OptionButton = _row(l, "weak_points").get_node("Line/Value")
	assert_int(weak.get_selected_id()).is_equal(0)
	weak.select(weak.get_item_index(1))
	weak.item_selected.emit(weak.get_item_index(1))
	var want: String = DataToggles.of_preset("normal").with_value(&"weak_points", 1).encode()
	assert_array(_sent(l)[-1][1]).is_equal([want])
	_lobby_event(l, want)
	assert_str((l.find_child("PresetName", true, false) as Label).text).is_equal("Normal (custom)")
	assert_bool(pressed.button_pressed).is_false()
	(
		assert_int(
			(_row(l, "weak_points").get_node("Line/Value") as OptionButton).get_selected_id()
		)
		. is_equal(1)
	)
	I18n.apply("pt_PT")
	assert_str((l.find_child("PresetName", true, false) as Label).text).is_equal(
		"Normal (personalizado)"
	)


# FT: FT-PAIR-017
# Summaries are exact, banded or hidden; a guest sees the set read-only; Start locks it.
func test_values_read_only_for_a_guest_and_locked_at_start() -> void:
	var l: LobbyScreen = _lobby()
	_lobby_event(l, "easy")
	var summaries: OptionButton = _row(l, "summaries").get_node("Line/Value")
	assert_int(summaries.item_count).is_equal(3)
	assert_int(summaries.get_selected_id()).is_equal(2)
	assert_bool(summaries.disabled).is_false()
	assert_int((_row(l, "chips").get_node("Line/Value") as OptionButton).item_count).is_equal(2)
	var guest: LobbyScreen = _lobby(false)
	_lobby_event(guest, "normal")
	(
		assert_bool((_row(guest, "summaries").get_node("Line/Value") as OptionButton).disabled)
		. is_true()
	)
	assert_bool((guest.find_child("Preset_easy", true, false) as Button).disabled).is_true()
	assert_str((guest.find_child("ToggleNote", true, false) as Label).text).is_equal(
		"Only the host changes these."
	)
	(guest.find_child("Preset_easy", true, false) as Button).pressed.emit()
	assert_array(_sent(guest)).is_empty()
	_lobby_event(l, "easy", true)
	assert_bool(summaries.disabled).is_true()
	assert_str((l.find_child("ToggleNote", true, false) as Label).text).is_equal(
		"Locked: the run has started."
	)
	(l.find_child("Preset_hard", true, false) as Button).pressed.emit()
	assert_array(_sent(l)).is_empty()
