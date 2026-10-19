extends GdUnitTestSuite
## The abandon vote as a pure rule (NetAbandonVote, T045, D128).


# FT: FT-NET-041
# More than half of the remaining connected crew abandon the ship: 2 of 2, 2 of 3,
# 3 of 4; a vote can be withdrawn, and only the remaining crew's votes count.
func test_votes_exceed_half_of_remaining_crew() -> void:
	assert_int(NetAbandonVote.needed(1)).is_equal(1)
	assert_int(NetAbandonVote.needed(2)).is_equal(2)
	assert_int(NetAbandonVote.needed(3)).is_equal(2)
	assert_int(NetAbandonVote.needed(4)).is_equal(3)
	var v: NetAbandonVote = NetAbandonVote.new()
	assert_bool(v.passes(2)).is_false()
	v.cast(1, "ana", true)
	assert_bool(v.passes(2)).is_false()
	v.cast(2, "bo", true)
	assert_bool(v.passes(2)).is_true()
	assert_array(v.names()).is_equal(["ana", "bo"])
	v.cast(1, "ana", false)
	assert_bool(v.passes(2)).is_false()
	assert_array(v.names()).is_equal(["bo"])
	v.cast(3, "cy", true)
	v.keep_only([2])
	assert_array(v.names()).is_equal(["bo"])
	assert_bool(v.passes(1)).is_true()
	assert_bool(v.passes(0)).is_false()
