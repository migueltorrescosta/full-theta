extends GdUnitTestSuite
## The Shakedown on touch (D321, D322, D323; owner's Training Re-check notes of 2026-10-31):
## every lesson step reads in touch words on a phone or tablet layout (no key names, no key on
## Next), every control it names is on that station's phone screen, the step card keeps clear
## of the station's controls in every page and orientation, the Weapons lesson ship has the
## mounts its steps ask for, and the top bar's full-screen icon shows where it should.
# FT: FT-MIS-039, FT-STN-005

const SETTINGS: String = "user://test_training_touch.cfg"
const STEPS: String = "res://content/training/steps.tres"
const LANGS: Array[String] = ["en", "pt_PT", "it"]
const STATIONS: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "captain"
]
## [size, insets, tablet]: a phone on its side, a phone upright, a tablet.
const FORMS: Array = [
	[Vector2i(844, 390), [47, 0, 47, 21], false],
	[Vector2i(390, 844), [0, 47, 0, 34], false],
	[Vector2i(1024, 768), [], true],
]
## Words a touch step never says (a key, a click, a pad button), in every language.
const KEY_WORDS: String = (
	"\\b(press|click|keys?|keyboard|mouse|wheel|shift|ctrl|alt|enter|esc|wasd|f\\d"
	+ "|pressiona|clica|tecla|teclas|teclado|rato|premi|clicca|tasto|tastiera)\\b"
)
## Names (translation keys) that need not be a button of the station's phone screen.
const NOT_BUTTONS: Array[String] = [
	"train.next",
	"overlay.title",
	"alert.red",
	"alert.yellow",
	"alert.normal",
	"intent.route_clear",
	"sci.short_active",
	"touch.fullscreen_exit",
	# The selection sheet's options: the sheet opens from the target's name (C4).
	"intent.ping",
	"sheet.mark_here",
	# Shown only while they can work or their own step is on (C3, StationPanel.lesson_wants;
	# tests/stations/helm/test_helm_tablet.gd checks that the step shows them).
	"touch.helm.dock",
	# Requests are picked in the sheet Ask opens (ux-13, PhoneFrame.open_request_sheet).
	"chip.boost",
	"chip.power",
	"chip.sensor_power",
	"chip.fabricate_probe",
	"comms.hold_fire",
	"eng.touch.cause",
	"eng.touch.claim",
	"touch.helm.jump",
	"weapons.touch_claim",
	# (test_a_step_shows_the_hidden_control_it_names checks these.)
	"comms.claim",
	"sci.claim",
	"sci.hack",
	"relay.launch",
	"relay.accept",
	"relay.decline",
	"relay.send_to",
]
## [station, intent, the control's name key] of the controls that hide while they can't act
## (C3) and that a Shakedown step names: the step shows them.
const LESSON_SHOWS: Array = [
	["comms", "claim", "comms.claim"],
	["science", "claim", "sci.claim"],
	["science", "sci_hack", "sci.hack"],
	["relay", "claim", "relay.launch"],
	["relay", "probe_launch", "relay.launch"],
	["relay", "accept", "relay.accept"],
	["relay", "decline", "relay.decline"],
	["relay", "mark_send", "relay.send_to"],
]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _steps() -> TrainingStepsDef:
	return load(STEPS) as TrainingStepsDef


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _screen(station: String, form: Array) -> StationScreen:
	SafeArea.simulate(form[1])
	LayoutMode.forced = LayoutMode.Kind.TOUCH if form[2] else -1
	_vp = auto_free(SubViewport.new())
	_vp.size = form[0]
	add_child(_vp)
	var ctx: StationContext = StationFixture.context(station, SETTINGS)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	_vp.add_child(s)
	await _frames(4)
	return s


## Shows `intent`'s step of the station on its banner.
func _show_step(s: StationScreen, station: String, intent: String) -> void:
	TrainingBanner.note(
		s.ctx.training,
		{
			"line": "shakedown.%s.%s" % [station, intent],
			"text": "Do the thing. {binding:%s}" % intent
		},
		func(_id: String) -> Array: return []
	)


func _pages(s: StationScreen) -> int:
	var p: StationPanel = s.panels[0]
	return p.pages.count() if p.pages != null else 1


func _page(s: StationScreen, i: int) -> void:
	var p: StationPanel = s.panels[0]
	if p.pages != null:
		p.pages.current = i
	await _frames(3)


# --- the words -------------------------------------------------------------------------


func test_every_step_has_touch_words_without_key_names_in_every_language() -> void:
	var re: RegEx = RegEx.create_from_string("(?i)" + KEY_WORDS)
	var missing: Array[String] = []
	var keyed: Array[String] = []
	for lang: String in LANGS:
		I18n.apply(lang)
		for step: TrainingStepDef in _steps().steps:
			if step.is_pair():
				var pair_text: String = tr(step.example)
				if re.search(pair_text) != null:
					keyed.append("%s %s: %s" % [lang, step.intent, pair_text])
				continue
			var text: String = TrainingBanner.touch_text(str(step.station), str(step.intent))
			if text == "":
				missing.append("%s %s.%s" % [lang, step.station, step.intent])
			elif "{" in text or re.search(text) != null:
				keyed.append("%s %s.%s: %s" % [lang, step.station, step.intent, text])
	assert_array(missing).override_failure_message("no touch words: %s" % [missing]).is_empty()
	assert_array(keyed).override_failure_message("key names: %s" % [keyed]).is_empty()


func test_every_control_a_step_names_is_on_the_stations_phone_screen() -> void:
	var by_station: Dictionary = {}
	for station: String in STATIONS:
		by_station[station] = []
	for lang: String in LANGS:
		I18n.apply(lang)
		for station: String in STATIONS:
			var texts: Array[String] = []
			for form: Array in FORMS.slice(0, 2):
				var s: StationScreen = await _screen(station, form)
				for i: int in _pages(s):
					await _page(s, i)
					for t: Dictionary in TapAudit.targets(s):
						texts.append(str(t["text"]).trim_prefix("stick "))
				s.queue_free()
				_vp.queue_free()
			by_station[station].append(texts)
	var names: RegEx = RegEx.create_from_string("\\{t:([a-z][a-z0-9_.]*)\\}")
	var absent: Array[String] = []
	for step: TrainingStepDef in _steps().steps:
		if step.is_pair():
			continue
		for key: String in [
			"train.touch.%s.%s" % [step.station, step.intent], "train.touch.%s" % step.intent
		]:
			var raw: String = _raw(key)
			if raw == "":
				continue
			for m: RegExMatch in names.search_all(raw):
				var name_key: String = m.get_string(1)
				if name_key in NOT_BUTTONS:
					continue
				for l: int in LANGS.size():
					I18n.apply(LANGS[l])
					var label: String = tr(name_key)
					var found: bool = by_station[str(step.station)][l].any(
						func(t: String) -> bool: return t.begins_with(label)
					)
					# Passive and Active are one button's two faces.
					if not found and name_key == "sci.short_passive":
						found = true
					if not found:
						absent.append(
							(
								"%s %s.%s names '%s' (%s)"
								% [LANGS[l], step.station, step.intent, label, name_key]
							)
						)
			break
	I18n.apply("en")
	(
		assert_array(absent)
		. override_failure_message("controls not on screen: %s" % [absent])
		. is_empty()
	)


# FT: FT-STN-005
# C3: a control hidden while it can't act (Claim with one player, Hack without access, Launch
# with no probe, Accept and Decline with nothing waiting, Send with no ally) shows while a
# Shakedown step names it, on a phone either way up and on a tablet, and hides again after.
func test_a_step_shows_the_hidden_control_it_names() -> void:
	var missing: Array[String] = []
	for c: Array in LESSON_SHOWS:
		for form: Array in FORMS:
			var s: StationScreen = await _screen(c[0], form)
			var here: String = "%s %s %s" % [c[0], c[1], form[0]]
			# (a tablet's HUD says "Send >" where a phone says "Send ▸")
			var label: String = tr(c[2]).trim_suffix(" ▸")
			if _shown(s, label):
				missing.append(here + ": shown before the step")
			s.ctx.training[c[0]] = {
				"line": "", "intent": c[1], "text": "", "example": "", "done": false
			}
			await _frames(3)
			if not _shown(s, label):
				missing.append(here + ": hidden during the step")
			s.ctx.training.erase(c[0])
			await _frames(3)
			if _shown(s, label):
				missing.append(here + ": still shown after the step")
			s.queue_free()
			_vp.queue_free()
	assert_array(missing).override_failure_message("%s" % [missing]).is_empty()


## Whether a visible tap target of the screen's current page starts with `label`.
func _shown(s: StationScreen, label: String) -> bool:
	return TapAudit.targets(s).any(
		func(t: Dictionary) -> bool: return str(t["text"]).begins_with(label)
	)


func _raw(key: String) -> String:
	I18n.apply("en")
	var t: String = TranslationServer.translate(key)
	return "" if t == key else t


# --- the banner follows the device -----------------------------------------------------


func test_a_touch_layout_gets_touch_words_and_a_desktop_gets_keys() -> void:
	var s: StationScreen = await _screen("helm", FORMS[0])
	_show_step(s, "helm", "all_stop")
	s.training.refresh()
	await _frames(2)
	assert_bool(s.training.touch_wording()).is_true()
	assert_str(s.training._text.text).contains("All stop")
	assert_bool("{" in s.training._text.text).is_false()
	assert_str(s.training._next.text).is_equal("Next")
	# A pad in use gets the pad's words (only with a pad connected).
	s.ctx.matcher.device = IntentTable.PAD
	assert_bool(s.training.touch_wording()).is_equal(Input.get_connected_joypads().is_empty())
	s.ctx.matcher.device = IntentTable.KBM
	# A tablet shows the desktop panels: its card keeps clear of the controls, its words are keys.
	var t: StationScreen = await _screen("helm", FORMS[2])
	_show_step(t, "helm", "all_stop")
	t.training.refresh()
	assert_bool(t.training.touch_layout()).is_true()
	assert_bool(t.training.touch_wording()).is_false()
	SafeArea.simulate([])
	var d: StationScreen = await _screen("helm", [Vector2i(1280, 720), [], false])
	_show_step(d, "helm", "all_stop")
	d.training.refresh()
	assert_bool(d.training.touch_wording()).is_false()
	assert_str(d.training._next.text).contains("(")
	assert_str(d.training._text.text).contains("All stop")


# FT: FT-MIS-039
func test_the_card_folds_to_one_line_and_back() -> void:
	var s: StationScreen = await _screen("weapons", FORMS[0])
	_show_step(s, "weapons", "fire")
	await _frames(6)
	var card: TrainingBanner = s.training
	assert_bool(card._text.clip_text).is_false()
	var tall: float = card.size.y
	card._fold.pressed.emit()
	await _frames(6)
	# Folded, the step reads in up to two wrapped lines beside Next.
	assert_int(card._text.max_lines_visible).is_equal(2)
	assert_float(card.size.y).is_less(tall)
	assert_bool(card._next.visible).is_true()
	assert_bool(card._next.is_visible_in_tree()).is_true()
	# A step that needs more than the folded row never folds by itself, so it is never cut.
	card._folded = false
	card._text.text = "Tap a part's column, then Add power, then tap Next to go on."
	card._width = TrainingBanner.WIDTHS[-1]
	card._squeezed = true
	assert_bool(card._folded_fits()).is_false()
	card._text.text = "Tap Next."
	assert_bool(card._folded_fits()).is_true()
	card._squeezed = false
	card._folded = true
	card._fold.pressed.emit()
	await _frames(6)
	assert_int(card._text.max_lines_visible).is_equal(-1)


# --- the card covers nothing -----------------------------------------------------------


func test_the_step_card_covers_no_control_on_any_page_in_any_orientation() -> void:
	var covered: Array[String] = []
	for station: String in STATIONS:
		var longest: String = ""
		var intent: String = ""
		for step: TrainingStepDef in _steps().track(StringName(station)):
			var t: String = TrainingBanner.touch_text(station, str(step.intent))
			if t.length() > longest.length():
				longest = t
				intent = str(step.intent)
		for form: Array in FORMS:
			var s: StationScreen = await _screen(station, form)
			_show_step(s, station, intent)
			for i: int in _pages(s):
				await _page(s, i)
				await _frames(6)
				var card: TrainingBanner = s.training
				var here: String = "%s %s page %d" % [station, form[0], i]
				if not card.visible:
					covered.append(here + ": no card")
					continue
				var rect: Rect2 = card.get_global_rect()
				if not SafeArea.tap_rect(card).encloses(rect):
					covered.append("%s: card outside the safe area %s" % [here, rect])
				for t: Dictionary in TapAudit.targets(s, card):
					if (t["rect"] as Rect2).intersects(rect):
						covered.append("%s: card covers %s" % [here, t["text"]])
				var report: Dictionary = TapAudit.check(s)
				for rule: String in ["under_min", "in_band", "outside_safe", "tight"]:
					if not (report[rule] as Array).is_empty() and not form[2]:
						covered.append("%s: %s %s" % [here, rule, report[rule]])
			s.queue_free()
			_vp.queue_free()
	assert_array(covered).override_failure_message("%s" % [covered]).is_empty()


# --- the ship --------------------------------------------------------------------------


# FT: FT-MIS-039
func test_the_shakedown_ship_has_the_four_mounts_its_steps_pick() -> void:
	var lib: DefLibrary = DefLibrary.new()
	var run: RunDef = lib.run(&"shakedown")
	assert_object(run.player_ship).is_not_null()
	assert_int(run.player_ship.mounts.size()).is_greater_equal(4)
	var ids: Array[StringName] = []
	for m: MountDef in run.player_ship.mounts:
		ids.append(m.id)
		assert_array(m.validate()).is_empty()
	assert_array(ids).contains_exactly_in_any_order([&"bow", &"port", &"starboard", &"dorsal"])
	# The run's corvette has bow, port and starboard (gp-12).
	assert_int(lib.run(&"m3_run").player_ship.mounts.size()).is_equal(3)
	assert_array(run.player_ship.validate()).is_empty()


# --- the full-screen icon --------------------------------------------------------------


# FT: FT-STN-005
func test_the_top_bar_has_a_48_px_fullscreen_icon_where_offered() -> void:
	for form: Array in FORMS:
		for forced: int in [0, 1]:
			FullscreenButton.forced = forced
			var s: StationScreen = await _screen("helm", form)
			var b: FullscreenToggle = s.top_bar.fullscreen
			assert_bool(b.visible).is_equal(forced == 1)
			if forced == 1:
				var r: Rect2 = b.get_global_rect()
				assert_float(r.size.x).is_greater_equal(UiTheme.TOUCH_PRIMARY - 0.5)
				assert_float(r.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY - 0.5)
				var bar: Rect2 = s.top_bar.get_global_rect()
				# At the right end of the bar, inside it.
				(
					assert_bool(bar.grow(0.5).encloses(r))
					. override_failure_message("%s: %s in %s" % [form[0], r, bar])
					. is_true()
				)
				assert_float(r.end.x).is_greater(bar.end.x - 120.0)
				for rule: String in ["under_min", "under_primary", "outside_safe", "tight"]:
					(
						assert_array(TapAudit.check(s)[rule])
						. override_failure_message(
							"%s %s %s" % [form[0], rule, TapAudit.check(s)[rule]]
						)
						. is_empty()
					)
			s.queue_free()
			_vp.queue_free()


# FT: FT-STN-005
func test_the_icon_toggles_between_enter_and_exit() -> void:
	FullscreenButton.forced = 1
	var s: StationScreen = await _screen("weapons", FORMS[0])
	var b: FullscreenToggle = s.top_bar.fullscreen
	FullscreenToggle.forced_on = 0
	b._refresh()
	assert_bool(FullscreenToggle.is_full()).is_false()
	assert_str(b.tooltip_text).is_equal(tr("touch.fullscreen"))
	FullscreenToggle.forced_on = 1
	b._refresh()
	assert_bool(FullscreenToggle.is_full()).is_true()
	assert_str(b.tooltip_text).is_equal(tr("touch.fullscreen_exit"))
	assert_str(b.action).is_equal(FullscreenToggle.ACTION)
	assert_str(b.text).is_empty()
	# The menu's own entry keeps its text and its action.
	assert_str(auto_free(FullscreenButton.new()).action).is_equal("fullscreen")


# FT: FT-STN-005
func test_the_lobby_has_the_icon_in_both_arrangements() -> void:
	FullscreenButton.forced = 1
	for form: Array in FORMS.slice(0, 2):
		SafeArea.simulate(form[1])
		var vp: SubViewport = auto_free(SubViewport.new())
		vp.size = form[0]
		add_child(vp)
		var ctx: StationContext = StationFixture.context("helm", SETTINGS)
		ctx.crew.lobby[0]["started"] = false
		var root: Control = Control.new()
		root.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vp.add_child(root)
		var l: LobbyScreen = LobbyScreen.new()
		l.setup(ctx)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(l)
		await _frames(14)
		var b: FullscreenToggle = l.find_child("FullscreenToggle", true, false)
		assert_object(b).is_not_null()
		assert_bool(b.is_visible_in_tree()).is_true()
		assert_float(b.get_global_rect().size.x).is_greater_equal(UiTheme.TOUCH_PRIMARY - 0.5)
		(
			assert_bool(SafeArea.safe_rect(l).encloses(b.get_global_rect()))
			. override_failure_message(
				"%s: %s in %s" % [form[0], b.get_global_rect(), SafeArea.safe_rect(l)]
			)
			. is_true()
		)
		for rule: String in ["under_min", "outside_safe", "tight"]:
			(
				assert_array(TapAudit.check(l)[rule])
				. override_failure_message("%s %s" % [form[0], rule])
				. is_empty()
			)
		vp.queue_free()
	FullscreenButton.forced = 0
	var hidden: LobbyScreen = LobbyScreen.new()
	hidden.setup(StationFixture.context("helm", SETTINGS))
	add_child(hidden)
	await _frames(3)
	assert_bool((hidden.find_child("FullscreenToggle", true, false) as Control).visible).is_false()
	hidden.queue_free()
