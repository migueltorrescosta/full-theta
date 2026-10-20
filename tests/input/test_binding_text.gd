extends GdUnitTestSuite
## BindingText: human text of bindings, through the session language.

var _locale: String


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")
	TranslationServer.set_locale(_locale)


# FT: FT-STN-009
func test_describes_every_grammar_form() -> void:
	assert_str(BindingText.describe("Alt+A")).is_equal("Alt+A")
	assert_str(BindingText.describe("Shift+MMB")).is_equal("Shift+Middle click")
	assert_str(BindingText.describe("long RB")).is_equal("hold RB")
	assert_str(BindingText.describe("View+X")).is_equal("View+X")
	assert_str(BindingText.describe("B,2")).is_equal("B, 2")
	assert_str(BindingText.describe("S/W")).is_equal("S / W")
	assert_str(BindingText.describe("MouseX")).is_equal("Mouse")
	assert_str(BindingText.describe("LB+LS_X")).is_equal("LB+Left stick left/right")
	assert_str(BindingText.describe("-RS_Y")).is_equal("Right stick up/down")
	assert_str(BindingText.describe("View+RS")).is_equal("View+Right stick")
	assert_str(BindingText.describe("Kp Add")).is_equal("Kp Add")
	assert_str(BindingText.describe("?")).is_equal("?")


# FT: FT-STN-009
func test_describe_all_joins_and_translates() -> void:
	assert_str(BindingText.describe_all(PackedStringArray(["Equal", "WheelUp"]))).is_equal(
		"Equal / Wheel up"
	)
	I18n.apply("pt_PT")
	assert_str(BindingText.describe("long R3")).is_equal("manter R3")
	assert_str(BindingText.describe("LMB")).is_equal("Clique esquerdo")
