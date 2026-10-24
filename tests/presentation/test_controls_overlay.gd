extends GdUnitTestSuite
## ControlsOverlay (FT-STN-011): rows from the live binding table, translated labels.
# FT: FT-STN-011, FT-M1-019


func before() -> void:
	I18n.apply("en")


func after() -> void:
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
	# Every label is the English text of its key in the string table, not the key.
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))
	for r: Dictionary in overlay.rows():
		var key: String = IntentTable.label_key(r["id"])
		assert_str(r["label"]).is_not_equal(key)
		assert_str(r["label"]).is_equal(table["strings"][key]["en"])


# FT: FT-STN-012
func test_heading_is_the_seat_role_summary() -> void:
	var overlay: ControlsOverlay = auto_free(ControlsOverlay.new())
	overlay.build(Bindings.new(), ["helm", "weapons"], IntentTable.KBM, "tactical")
	assert_array(_texts(overlay)).contains([tr("role.tactical")])
	overlay.build(Bindings.new(), ["helm"], IntentTable.KBM)
	assert_array(_texts(overlay)).not_contains([tr("role.tactical")])


# FT: FT-STN-011, FT-AUD-013
func test_a_language_switch_retranslates_the_open_overlay() -> void:
	var overlay: ControlsOverlay = auto_free(ControlsOverlay.new())
	add_child(overlay)
	overlay.build(Bindings.new(), ["helm"], IntentTable.KBM, "helm")
	var before_texts: Array[String] = _texts(overlay)
	assert_array(before_texts).contains(["Controls", tr("role.helm")])
	I18n.apply("it")
	var after_texts: Array[String] = _texts(overlay)
	assert_array(after_texts).contains(["Comandi", tr("role.helm")])
	assert_str(_row(overlay, "face")["label"]).is_equal(tr(IntentTable.label_key("face")))
	assert_str(_row(overlay, "face")["label"]).is_not_equal("Face selection")
	assert_array(after_texts).is_not_equal(before_texts)


func _texts(overlay: ControlsOverlay) -> Array[String]:
	var out: Array[String] = []
	for l: Node in overlay.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out
