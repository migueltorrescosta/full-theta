extends GdUnitTestSuite
## Claims as a pure rule (NetClaims, T044).

const ITEMS: Dictionary = {
	"helm": ["flight", "shield_facing"], "weapons": ["mount:0", "mount:1"], "engineering": []
}


# FT: FT-NET-022, FT-NET-023
# A claimed item belongs to its claimer until released; another session can't claim
# it; an unclaimed item has no holder.
func test_claim_and_release() -> void:
	var c: NetClaims = NetClaims.new()
	assert_int(c.holder(0, "mount:0")).is_equal(-1)
	assert_bool(c.claim(0, "mount:0", 1)).is_true()
	assert_bool(c.claim(0, "mount:0", 1)).is_true()
	assert_bool(c.claim(0, "mount:0", 2)).is_false()
	assert_int(c.holder(0, "mount:0")).is_equal(1)
	assert_int(c.holder(1, "mount:0")).is_equal(-1)
	assert_bool(c.release(0, "mount:0", 2)).is_false()
	assert_bool(c.release(0, "mount:0", 1)).is_true()
	assert_int(c.holder(0, "mount:0")).is_equal(-1)


# FT: FT-NET-044
# A session alone on a station holds every free item of it; with two sessions on the
# station nothing is claimed automatically, and the first keeps what it held.
func test_alone_on_a_station_holds_its_claims() -> void:
	var c: NetClaims = NetClaims.new()
	var got: Array = c.settle(0, {"helm": [1], "weapons": [1, 2]}, ITEMS)
	assert_array(got).is_equal([["flight", 1], ["shield_facing", 1]])
	assert_dict(c.table(0)).is_equal({"flight": 1, "shield_facing": 1})
	c.settle(0, {"helm": [1, 3], "weapons": [2]}, ITEMS)
	assert_dict(c.table(0)).is_equal({"flight": 1, "shield_facing": 1, "mount:0": 2, "mount:1": 2})


# FT: FT-NET-024
# A station change releases the claims of the stations the new pick no longer covers;
# a lapse (grace expiry) releases them all.
func test_station_change_and_lapse_release() -> void:
	var c: NetClaims = NetClaims.new()
	c.claim(0, "flight", 1)
	c.claim(0, "mount:0", 1)
	c.claim(0, "mount:1", 2)
	assert_array(c.release_session(1, ["helm"])).is_equal([[0, "mount:0"]])
	assert_array(c.items_of(0, 1)).is_equal(["flight"])
	assert_array(c.release_session(1)).is_equal([[0, "flight"]])
	assert_dict(c.table(0)).is_equal({"mount:1": 2})
