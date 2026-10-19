extends GdUnitTestSuite
## FirstRunTooltip (FT-STN-012).

const INTENTS: Array[String] = ["face", "approach", "helm_radial", "all_stop"]


func before() -> void:
	I18n.apply("en")


# FT: FT-STN-012
func test_shown_once_per_station() -> void:
	var tip: FirstRunTooltip = auto_free(FirstRunTooltip.new())
	var settings: ClientSettings = ClientSettings.new("user://test_tooltip.cfg")
	var gone: Array[String] = []
	tip.dismissed.connect(func(s: String) -> void: gone.append(s))
	assert_bool(tip.show_for("helm", INTENTS, settings.bindings, "kbm", settings)).is_true()
	assert_bool(tip.visible).is_true()
	tip.got_it.pressed.emit()
	assert_bool(tip.visible).is_false()
	assert_array(gone).is_equal(["helm"])
	assert_bool(settings.tooltip_seen("helm")).is_true()
	assert_bool(tip.show_for("helm", INTENTS, settings.bindings, "kbm", settings)).is_false()
	# Another station still gets its own; the X dismisses too.
	assert_bool(tip.show_for("weapons", ["fire"], settings.bindings, "kbm", settings)).is_true()
	tip.close.pressed.emit()
	assert_bool(settings.tooltip_seen("weapons")).is_true()


# FT: FT-STN-012
func test_reset_tooltips_reenables() -> void:
	var tip: FirstRunTooltip = auto_free(FirstRunTooltip.new())
	var settings: ClientSettings = ClientSettings.new("user://test_tooltip.cfg")
	settings.mark_tooltip_seen("helm")
	assert_bool(tip.show_for("helm", INTENTS, settings.bindings, "kbm", settings)).is_false()
	settings.reset_tooltips()
	assert_bool(tip.show_for("helm", INTENTS, settings.bindings, "kbm", settings)).is_true()


# FT: FT-STN-012
func test_text_is_controls_only() -> void:
	var tip: FirstRunTooltip = auto_free(FirstRunTooltip.new())
	var settings: ClientSettings = ClientSettings.new("user://test_tooltip.cfg")
	var b: Bindings = settings.bindings
	tip.show_for("helm", INTENTS, b, "kbm", settings)
	var want: Array[String] = []
	for id: String in INTENTS:
		if not b.bindings(id, "kbm").is_empty():
			want.append(
				(
					"%s: %s"
					% [
						tr(IntentTable.label_key(id)),
						BindingText.describe_all(b.bindings(id, "kbm"))
					]
				)
			)
	# helm_radial is pad-only: left out on KB/M.
	assert_int(want.size()).is_equal(3)
	assert_array(tip.lines()).is_equal(want)
