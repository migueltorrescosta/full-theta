extends GdUnitTestSuite
## NumberWords (shared/number_words.gd): the fragment keys a number is stitched from,
## per language and gender, and that every key exists in content/dialogue/numbers.json.

var _fragments: Dictionary = {}


func before() -> void:
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/dialogue/numbers.json")
	)
	for lang: String in data["languages"]:
		_fragments[lang] = data["languages"][lang]["fragments"]


func _keys(n: int, lang: String, feminine: bool = false) -> Array:
	return Array(NumberWords.compose(n, lang, feminine))


# FT: FT-AUD-018
func test_english() -> void:
	assert_array(_keys(342, "en")).is_equal(["3", "hundred", "and", "42"])
	assert_array(_keys(100, "en")).is_equal(["1", "hundred"])
	assert_array(_keys(101, "en")).is_equal(["1", "hundred", "and", "1"])
	assert_array(_keys(1000, "en")).is_equal(["1", "thousand"])
	assert_array(_keys(1200, "en")).is_equal(["1", "thousand", "2", "hundred"])
	assert_array(_keys(2342, "en")).is_equal(["2", "thousand", "3", "hundred", "and", "42"])
	assert_array(_keys(2005, "en")).is_equal(["2", "thousand", "and", "5"])
	assert_array(_keys(21000, "en")).is_equal(["21", "thousand"])
	assert_array(_keys(0, "en")).is_equal(["0"])
	assert_array(_keys(-7, "en")).is_equal(["minus", "7"])
	assert_array(_keys(-342, "en")).is_equal(["minus", "3", "hundred", "and", "42"])
	# English has no gender in these fragments.
	assert_array(_keys(2, "en", true)).is_equal(["2"])


# FT: FT-AUD-018
func test_european_portuguese() -> void:
	assert_array(_keys(342, "pt_PT")).is_equal(["c3", "e", "42"])
	assert_array(_keys(100, "pt_PT")).is_equal(["c100"])
	assert_array(_keys(101, "pt_PT")).is_equal(["c1", "e", "1"])
	assert_array(_keys(1000, "pt_PT")).is_equal(["mil"])
	assert_array(_keys(1200, "pt_PT")).is_equal(["mil", "e", "c2"])
	assert_array(_keys(2342, "pt_PT")).is_equal(["2", "mil", "c3", "e", "42"])
	assert_array(_keys(21000, "pt_PT")).is_equal(["21", "mil"])
	assert_array(_keys(-5, "pt_PT")).is_equal(["menos", "5"])
	# Feminine: duas, duzentas, vinte e uma; 11 and 12 have no feminine form.
	assert_array(_keys(2, "pt_PT", true)).is_equal(["f2"])
	assert_array(_keys(200, "pt_PT", true)).is_equal(["cf2"])
	assert_array(_keys(21, "pt_PT", true)).is_equal(["f21"])
	assert_array(_keys(12, "pt_PT", true)).is_equal(["12"])
	assert_array(_keys(100, "pt_PT", true)).is_equal(["c100"])
	assert_array(_keys(2000, "pt_PT", true)).is_equal(["f2", "mil"])
	assert_array(_keys(2, "pt_PT")).is_equal(["2"])
	assert_array(_keys(200, "pt_PT")).is_equal(["c2"])


# FT: FT-AUD-018
func test_italian() -> void:
	assert_array(_keys(342, "it")).is_equal(["c3", "42"])
	assert_array(_keys(100, "it")).is_equal(["c1"])
	assert_array(_keys(101, "it")).is_equal(["c1", "1"])
	assert_array(_keys(1000, "it")).is_equal(["mille"])
	assert_array(_keys(1200, "it")).is_equal(["mille", "c2"])
	assert_array(_keys(2000, "it")).is_equal(["2", "mila"])
	assert_array(_keys(2342, "it")).is_equal(["2", "mila", "c3", "42"])
	assert_array(_keys(21000, "it")).is_equal(["21", "mila"])
	assert_array(_keys(-9, "it")).is_equal(["meno", "9"])
	# Feminine "una" for one only.
	assert_array(_keys(1, "it", true)).is_equal(["f1"])
	assert_array(_keys(1, "it")).is_equal(["1"])
	assert_array(_keys(2, "it", true)).is_equal(["2"])
	# Compounds keep the masculine form, like ventuno: centouno, milleuno.
	assert_array(_keys(21, "it", true)).is_equal(["21"])
	assert_array(_keys(101, "it", true)).is_equal(["c1", "1"])
	assert_array(_keys(1001, "it", true)).is_equal(["mille", "1"])


# FT: FT-AUD-018
# Values beyond +-999,999 are clamped.
func test_clamps_to_the_limit() -> void:
	assert_array(_keys(5_000_000, "en")).is_equal(_keys(999_999, "en"))
	assert_array(_keys(-5_000_000, "it")).is_equal(_keys(-999_999, "it"))


# FT: FT-AUD-018
# Every key compose() yields for 0..999,999 (all of 0..2,000, then a dense stride),
# masculine and feminine, negatives included, is a numbers.json fragment of that
# language, so a stitched number never misses a clip.
func test_every_composed_key_is_a_fragment() -> void:
	var values: PackedInt32Array = PackedInt32Array()
	for n: int in 2001:
		values.append(n)
	var n2: int = 2001
	while n2 <= 999_999:
		values.append(n2)
		n2 += 97
	values.append_array(
		PackedInt32Array([999_999, 100_000, 101_000, 200_200, 21_021, -1, -999_999])
	)
	for lang: String in ["en", "pt_PT", "it"]:
		var known: Dictionary = _fragments[lang]
		var missing: Dictionary = {}
		for n: int in values:
			for feminine: bool in [false, true]:
				for key: String in NumberWords.compose(n, lang, feminine):
					if not known.has(key):
						missing[key] = n
		assert_dict(missing).override_failure_message("%s: %s" % [lang, missing]).is_empty()
