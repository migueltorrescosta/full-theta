extends GdUnitTestSuite
## Hold-to-explain on jargon buttons (D6, R26-4, R26-11): the line comes from the `help.*`
## strings the Controls page already shows; no button is renamed.


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")


# FT: FT-STN-005
func test_the_jargon_buttons_have_a_line_from_the_existing_help_strings() -> void:
	assert_str(HoldHelp.explain("Cause")).is_equal(tr("help.eng.cause"))
	assert_str(HoldHelp.explain("Probe")).is_equal(tr("help.eng.probe"))
	assert_str(HoldHelp.explain("Harden")).is_equal(tr("help.eng.harden"))
	assert_str(HoldHelp.explain("Hold fire")).is_equal(tr("help.comms.hold_fire"))
	# A label with a suffix ("Claim A", the crew's letter) finds its box ("Claim").
	assert_str(HoldHelp.explain("Claim A")).is_equal(tr("help.eng.claim"))
	assert_str(HoldHelp.explain("No such button")).is_empty()


# FT: FT-STN-005
func test_the_line_follows_the_language() -> void:
	var en: String = HoldHelp.explain("Cause")
	I18n.apply("it")
	var it: String = HoldHelp.explain(tr("eng.touch.cause"))
	assert_str(it).is_not_empty()
	assert_str(it).is_not_equal(en)


# FT: FT-STN-005
func test_a_long_touch_shows_the_bubble_and_is_no_tap() -> void:
	var holder: Control = auto_free(Control.new())
	holder.size = Vector2(844, 390)
	add_child(holder)
	var b: RailButton = RailButton.make("Cause")
	b.position = Vector2(100, 200)
	b.size = Vector2(76, 48)
	holder.add_child(b)
	var taps: Array[bool] = []
	b.pressed.connect(func() -> void: taps.append(true))
	assert_str(b._get_tooltip(Vector2.ZERO)).is_equal(tr("help.eng.cause"))
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = 0
	t.position = Vector2(10, 10)
	t.pressed = true
	b._gui_input(t)
	b._explain(0)
	assert_object(b.get_node_or_null("HoldHelp")).is_not_null()
	assert_str((b.get_node("HoldHelp").get_child(0) as Label).text).is_equal(tr("help.eng.cause"))
	t = t.duplicate()
	t.pressed = false
	b._gui_input(t)
	assert_array(taps).is_empty()
	# A short touch is still a tap.
	t.pressed = true
	b._gui_input(t)
	t = t.duplicate()
	t.pressed = false
	b._gui_input(t)
	assert_array(taps).has_size(1)


# FT: FT-STN-005
func test_hold_buttons_are_not_explained() -> void:
	var b: RailButton = RailButton.make("Cause")
	b.hold = true
	add_child(auto_free(b))
	b._explain(-1)
	assert_object(b.get_node_or_null("HoldHelp")).is_null()
