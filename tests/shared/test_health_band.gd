extends GdUnitTestSuite
## The four bands of a banded summary (HealthBand, D193).

const EDGES: PackedFloat64Array = [0.75, 0.5, 0.25]


# FT: FT-PAIR-019
# D193: ok, scratched, damaged and critical, split at 75, 50 and 25 % of the maximum; a
# share on an edge belongs to the better band; each band has a word and a shape of its own
# (FT-STN-006).
func test_bands_split_at_75_50_and_25_percent() -> void:
	var cases: Array = [
		[1.0, HealthBand.Band.OK],
		[0.75, HealthBand.Band.OK],
		[0.7499, HealthBand.Band.SCRATCHED],
		[0.5, HealthBand.Band.SCRATCHED],
		[0.4999, HealthBand.Band.DAMAGED],
		[0.25, HealthBand.Band.DAMAGED],
		[0.2499, HealthBand.Band.CRITICAL],
		[0.0, HealthBand.Band.CRITICAL],
		[-1.0, HealthBand.Band.CRITICAL],
		[INF, HealthBand.Band.OK],
		[NAN, HealthBand.Band.CRITICAL],
	]
	for c: Array in cases:
		assert_int(HealthBand.band_of(c[0], EDGES)).override_failure_message(str(c[0])).is_equal(
			c[1]
		)
	var words: Array = [0, 1, 2, 3].map(func(b: int) -> String: return HealthBand.word(b))
	assert_array(words).is_equal(["ok", "scratched", "damaged", "critical"])
	var shapes: Dictionary = {}
	for b: int in 4:
		shapes[HealthBand.shape(b)] = true
	assert_int(shapes.size()).is_equal(4)


# FT: FT-PAIR-019
# A banded value is the middle of its band, so it falls back into the same band and never
# tells a share closer than the band does.
func test_a_banded_share_is_the_middle_of_its_band() -> void:
	assert_float(HealthBand.middle(HealthBand.Band.OK, EDGES)).is_equal_approx(0.875, 1e-9)
	assert_float(HealthBand.middle(HealthBand.Band.SCRATCHED, EDGES)).is_equal_approx(0.625, 1e-9)
	assert_float(HealthBand.middle(HealthBand.Band.DAMAGED, EDGES)).is_equal_approx(0.375, 1e-9)
	assert_float(HealthBand.middle(HealthBand.Band.CRITICAL, EDGES)).is_equal_approx(0.125, 1e-9)
	for share: float in [0.0, 0.1, 0.3, 0.6, 0.8, 1.0]:
		var q: float = HealthBand.quantise(share, EDGES)
		assert_int(HealthBand.band_of(q, EDGES)).is_equal(HealthBand.band_of(share, EDGES))
		assert_float(HealthBand.quantise(q, EDGES)).is_equal_approx(q, 1e-9)


# FT: FT-PAIR-019
# The split points are data: the toggle file holds the D193 values.
func test_the_split_points_are_in_the_toggle_file() -> void:
	assert_array(Array(DataToggles.def().band_edges)).is_equal([0.75, 0.5, 0.25])
