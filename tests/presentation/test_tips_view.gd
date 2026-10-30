extends GdUnitTestSuite
## TipsView (#28, P28-Tips, P28-LoadBar): the tips of content/tips/tips.json in the UI
## language, each for max(5 s, characters / 15 + 1 s), a tap on the left half back and on
## the right half forward, the player's topics first, and a thin bar for a given progress.


func after_test() -> void:
	I18n.apply("en")


func _view(lang: String = "en") -> TipsView:
	I18n.apply(lang)
	var v: TipsView = auto_free(TipsView.new())
	v.shuffle_seed = 3
	v.size = Vector2(844, 390)
	add_child(v)
	return v


func _tap(v: TipsView, x: float) -> void:
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(x, 200)
	v._gui_input(up)


# FT: FT-M1-019
func test_each_tip_stays_for_the_owners_time() -> void:
	assert_float(TipsView.seconds_for("Short tip.")).is_equal(5.0)
	var long: String = "x".repeat(90)
	assert_float(TipsView.seconds_for(long)).is_equal_approx(7.0, 0.001)
	var v: TipsView = _view()
	var first: Dictionary = v.current()
	var stay: float = TipsView.seconds_for(str(first["text"]))
	v.tick(stay - 0.1)
	assert_str(str(v.current()["id"])).is_equal(str(first["id"]))
	v.tick(0.2)
	assert_str(str(v.current()["id"])).is_not_equal(str(first["id"]))
	assert_float(v.shown_for).is_equal(0.0)
	v.autoplay = false
	v.tick(60.0)
	assert_int(v.index).is_equal(1)


# FT: FT-M1-019
func test_taps_go_back_and_forward_and_wrap_round() -> void:
	var v: TipsView = _view()
	_tap(v, 600)
	assert_int(v.index).is_equal(1)
	_tap(v, 100)
	_tap(v, 100)
	assert_int(v.index).is_equal(v.tips.size() - 1)
	(v.find_child("Next", true, false) as Button).pressed.emit()
	assert_int(v.index).is_equal(0)
	assert_str((v.find_child("Tip", true, false) as Label).text).is_equal(str(v.current()["text"]))


# FT: FT-M1-019
func test_every_tip_loads_in_the_ui_language_with_the_players_topics_first() -> void:
	var v: TipsView = _view("pt_PT")
	var data: Dictionary = TipsView.read()
	assert_int(v.tips.size()).is_equal((data["tips"] as Array).size())
	assert_int(v.tips.size()).is_greater_equal(100)
	var only: Array[String] = ["engineering", "modes"]
	v.prefer(only)
	var seen: Array = []
	for i: int in v.tips.size():
		seen.append(str(v.tips[i]["topic"]) in only)
	var firsts: int = seen.count(true)
	assert_int(firsts).is_greater_equal(5)
	assert_array(seen.slice(0, firsts)).not_contains([false])
	var tip: Dictionary = v.current()
	for t: Dictionary in data["tips"]:
		if t["id"] == tip["id"]:
			assert_str(str(tip["text"])).is_equal(str(t["pt_PT"]))
	assert_array(["ENGENHARIA", "MODOS"]).contains(
		[(v.find_child("Topic", true, false) as Label).text]
	)
	assert_str(TipsView.text_of({"en": "Hi"}, "it")).is_equal("Hi")


# FT: FT-M1-019
func test_the_bar_shows_only_with_a_progress() -> void:
	var v: TipsView = _view()
	var bar: Control = v.find_child("Bar", true, false)
	assert_bool(bar.visible).is_false()
	v.set_progress(0.62, tr("tips.loading") % 62)
	assert_bool(bar.visible).is_true()
	assert_float(v.progress).is_equal(0.62)
	assert_str((v.find_child("Status", true, false) as Label).text).contains("62 %")
	v.set_progress(2.0)
	assert_float(v.progress).is_equal(1.0)
	v.set_progress(-1.0)
	assert_bool(bar.visible).is_false()
	# The tip, the bar and the arrows stay inside the view, side by side in landscape.
	await get_tree().process_frame
	var tip: Control = v.find_child("Tip", true, false)
	var back: Control = v.find_child("Back", true, false)
	assert_float(back.position.x + back.size.x).is_less_equal(tip.position.x)
	assert_bool(Rect2(Vector2.ZERO, v.size).encloses(tip.get_rect())).is_true()
