extends GdUnitTestSuite
## The abandon vote as a pure rule (NetVote, T045, D128).


# FT: FT-NET-041
# More than half of the remaining connected crew abandon the ship: 2 of 2, 2 of 3,
# 3 of 4; a vote can be withdrawn, and only the remaining crew's votes count.
func test_votes_exceed_half_of_remaining_crew() -> void:
	assert_int(NetVote.needed(1)).is_equal(1)
	assert_int(NetVote.needed(2)).is_equal(2)
	assert_int(NetVote.needed(3)).is_equal(2)
	assert_int(NetVote.needed(4)).is_equal(3)
	var v: NetVote = NetVote.new()
	assert_bool(v.passes(2)).is_false()
	v.cast(1, "ana", true)
	assert_bool(v.passes(2)).is_false()
	v.cast(2, "bo", true)
	assert_bool(v.passes(2)).is_true()
	assert_array(v.names()).is_equal(["ana", "bo"])
	assert_array(v.sessions()).is_equal([1, 2])
	v.cast(1, "ana", false)
	assert_bool(v.passes(2)).is_false()
	assert_array(v.names()).is_equal(["bo"])
	v.cast(3, "cy", true)
	v.keep_only([2])
	assert_array(v.names()).is_equal(["bo"])
	assert_bool(v.passes(1)).is_true()
	assert_bool(v.passes(0)).is_false()


# FT: FT-NET-041
# G7: one vote object for the abandon, run reset and relaunch votes, keyed by session: two crew
# who share a name hold separate votes, one withdrawing does not take the other's away, and the
# payload carries the session ids a client finds its own vote by.
func test_votes_are_keyed_by_session_not_name() -> void:
	var ana: NetSession = NetSession.new(1, 10.0, 10.0)
	ana.name = "Ana"
	var twin: NetSession = NetSession.new(2, 10.0, 10.0)
	twin.name = "Ana"
	var members: Array[int] = [1, 2, 3]
	var v: NetVote = NetVote.new()
	assert_bool(v.cast_from(ana, true, members)).is_false()
	assert_bool(v.cast_from(twin, true, members)).is_true()
	assert_dict(v.payload(7, 3)).is_equal(
		{"ship": 7, "voters": ["Ana", "Ana"], "sessions": [1, 2], "needed": 2}
	)
	assert_bool(v.cast_from(twin, false, members)).is_false()
	assert_array(v.sessions()).is_equal([1])
	# A session that left the crew loses its vote when the next one is cast.
	assert_bool(v.cast_from(twin, true, [2, 3])).is_false()
	assert_array(v.sessions()).is_equal([2])
