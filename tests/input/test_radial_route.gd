extends GdUnitTestSuite
## A controller player is told the Helm radial route for the Helm actions that have no button
## of their own (D1, R25-1, R25-12): the Shakedown text and the Controls page.


func before_test() -> void:
	I18n.apply("en")


# FT: FT-HLM-017, FT-MIS-039
func test_an_unbound_radial_action_names_the_route_on_a_pad_only() -> void:
	var b: Bindings = Bindings.new()
	var line: String = "Align a mount to the target. {binding:align}"
	assert_str(BindingText.fill_markers(line, b, IntentTable.PAD)).is_equal(
		"Align a mount to the target. Helm menu › Align"
	)
	assert_str(BindingText.fill_markers(line, b, IntentTable.KBM)).is_equal(
		"Align a mount to the target. L"
	)
	# An action with a pad button of its own keeps it; one outside the radial still says "-".
	assert_str(BindingText.fill_markers("{binding:face}", b, IntentTable.PAD)).is_equal("L3")
	assert_str(BindingText.fill_markers("{binding:mark_rename}", b, IntentTable.PAD)).is_equal("-")


# FT: FT-HLM-017
func test_the_route_follows_a_rebound_radial_button() -> void:
	var b: Bindings = Bindings.new()
	b.rebind("helm_radial", IntentTable.PAD, PackedStringArray(["View+LS"]))
	assert_str(BindingText.radial_route("dock", b, IntentTable.PAD)).is_equal(
		"hold View+Left stick, flick to Dock"
	)


# FT: FT-HLM-017, FT-STN-011
func test_the_pad_diagram_does_not_call_radial_actions_unbound() -> void:
	var m: ControlsModel = ControlsModel.new()
	m.build(Bindings.new(), ["helm"], IntentTable.PAD)
	var unbound: Array[String] = m.unbound_here()
	for id: String in HelmPanel.RADIAL:
		assert_array(unbound).not_contains([id])
	assert_array(unbound).not_contains(["alert_cycle"])
	assert_array(m.radial_here()).is_equal(
		["chase_camera", "align", "decoupled", "shield_track", "dock", "jump"]
	)
	# Genuinely unbound controller actions stay listed, and the keyboard model is unchanged.
	assert_array(unbound).contains(["helm_pointer"])
	var kbm: ControlsModel = ControlsModel.new()
	kbm.build(Bindings.new(), ["helm"], IntentTable.KBM)
	assert_array(kbm.radial_here()).is_empty()
	# Unbind the radial itself and its items are unbound again.
	var b: Bindings = Bindings.new()
	b.rebind("helm_radial", IntentTable.PAD, PackedStringArray())
	m.build(b, ["helm"], IntentTable.PAD)
	assert_array(m.unbound_here()).contains(["align"])
