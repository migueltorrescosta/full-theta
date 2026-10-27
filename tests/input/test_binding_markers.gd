extends GdUnitTestSuite
## The binding slot of a dialogue line (FT-MIS-039, FT-AUD-010): the server leaves a
## `{binding:<intent>}` marker in the subtitle, nothing voices it, and the client fills it
## with the player's current binding.

const LINE: Dictionary = {
	"id": "shakedown.helm.face",
	"slots": {"binding": {"kind": "binding", "intent": "face"}},
}


# FT: FT-AUD-010, FT-MIS-039
func test_fill_leaves_a_marker_for_the_client() -> void:
	var text: String = DialogueLines.fill(LINE, "Face the drone. {binding}", {})
	assert_str(text).is_equal("Face the drone. {binding:face}")


# FT: FT-AUD-010, FT-MIS-039
func test_a_line_with_only_binding_slots_is_not_stitched() -> void:
	assert_bool(DialogueLines.has_voiced_slots(LINE)).is_false()
	var mixed: Dictionary = {
		"slots": {"binding": {"kind": "binding", "intent": "face"}, "n": "number"}
	}
	assert_bool(DialogueLines.has_voiced_slots(mixed)).is_true()
	assert_bool(DialogueLines.has_voiced_slots({})).is_false()


# FT: FT-MIS-039
func test_the_client_fills_the_marker_with_the_current_binding() -> void:
	var b: Bindings = Bindings.new()
	var text: String = "Face the drone. {binding:face}"
	assert_str(BindingText.fill_markers(text, b, IntentTable.KBM)).is_equal("Face the drone. F")
	assert_str(BindingText.fill_markers(text, b, IntentTable.PAD)).is_equal("Face the drone. L3")
	b.rebind("face", IntentTable.KBM, PackedStringArray(["Alt+A"]))
	assert_str(BindingText.fill_markers(text, b, IntentTable.KBM)).is_equal("Face the drone. Alt+A")
	# No binding on the device: a dash, not a gap.
	assert_str(BindingText.fill_markers("{binding:decoupled}", b, IntentTable.PAD)).is_equal("-")
	assert_str(BindingText.fill_markers("no marker", b, IntentTable.KBM)).is_equal("no marker")
