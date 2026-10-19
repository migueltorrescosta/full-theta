extends GdUnitTestSuite
## ControlsOverlay (FT-STN-011): rows from the live binding table, translated labels.
# FT: FT-STN-011


func before() -> void:
	I18n.apply("en")


func _row(overlay: ControlsOverlay, id: String) -> Dictionary:
	for r: Dictionary in overlay.rows():
		if r["id"] == id:
			return r
	return {}


func test_rows_come_from_the_live_table() -> void:
	var overlay: ControlsOverlay = auto_free(ControlsOverlay.new())
	var bindings: Bindings = Bindings.new()
	overlay.build(bindings, ["helm"], IntentTable.KBM)
	var ids: Array = overlay.rows().map(func(r: Dictionary) -> String: return r["id"])
	var want: Array = []
	for group: String in [IntentTable.COMMON, IntentTable.LIVE, "helm"]:
		for id: String in IntentTable.ids_of(group):
			if not bindings.bindings(id, IntentTable.KBM).is_empty():
				want.append(id)
	assert_array(ids).is_equal(want)
	# Pad-only intents are left out on KB/M; another station's intents never appear.
	assert_array(ids).not_contains(["alert_red", "helm_radial", "fire"])
	assert_str(_row(overlay, "select")["section"]).is_equal("overlay.common")
	assert_str(_row(overlay, "face")["section"]).is_equal("station.helm")
	assert_str(_row(overlay, "face")["keys"]).is_equal(BindingText.describe_all(["F"]))
	overlay.build(bindings, ["helm"], IntentTable.PAD)
	assert_str(_row(overlay, "alert_red")["keys"]).is_equal(BindingText.describe_all(["View+Up"]))


func test_a_rebind_shows_at_once() -> void:
	var overlay: ControlsOverlay = auto_free(ControlsOverlay.new())
	var bindings: Bindings = Bindings.new()
	overlay.build(bindings, ["helm"], IntentTable.KBM)
	bindings.rebind("face", IntentTable.KBM, PackedStringArray(["Shift+F"]))
	assert_str(_row(overlay, "face")["keys"]).is_equal(BindingText.describe_all(["Shift+F"]))
	bindings.set_toggle("face", true)
	assert_str(_row(overlay, "face")["keys"]).ends_with(" (toggle)")
	bindings.rebind("face", IntentTable.KBM, PackedStringArray())
	assert_dict(_row(overlay, "face")).is_empty()


func test_labels_are_translated() -> void:
	var overlay: ControlsOverlay = auto_free(ControlsOverlay.new())
	overlay.build(Bindings.new(), ["helm"], IntentTable.KBM)
	assert_str(_row(overlay, "face")["label"]).is_equal("Face selection")
	for r: Dictionary in overlay.rows():
		assert_str(r["label"]).is_equal(tr(IntentTable.label_key(r["id"])))
