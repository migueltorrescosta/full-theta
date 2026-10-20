extends GdUnitTestSuite
## Stall policy, event inbox and outbox, session tokens and the rate limit (promoted
## from the S4 spike tests).

const NONE: NetResync.Action = NetResync.Action.NONE
const DELTA: NetResync.Action = NetResync.Action.DELTA
const FULL: NetResync.Action = NetResync.Action.FULL


func _send(r: NetResync, seq: int) -> NetResync.Action:
	var action: NetResync.Action = r.decide(0)
	if action != NONE:
		r.on_sent(seq, action == FULL)
	return action


# FT: FT-NET-037
func test_join_gets_full_then_deltas() -> void:
	var r: NetResync = NetResync.new(15)
	assert_int(_send(r, 1)).is_equal(FULL)
	assert_int(_send(r, 2)).is_equal(DELTA)
	r.on_ack(2)
	assert_int(r.acked_seq).is_equal(2)


# FT: FT-NET-037
# A client that couldn't apply a snapshot acks -1: the next snapshot is one full one,
# then deltas again; its acks still count.
func test_ack_minus_one_gets_one_full_snapshot() -> void:
	var r: NetResync = NetResync.new(NetResync.LAG_LIMIT)
	_send(r, 1)
	_send(r, 2)
	r.on_ack(-1)
	assert_int(r.acked_seq).is_equal(-1)
	assert_bool(r.holds_events()).is_true()
	assert_int(_send(r, 3)).is_equal(FULL)
	assert_int(_send(r, 4)).is_equal(DELTA)
	r.on_ack(3)
	assert_int(r.acked_seq).is_equal(3)
	assert_int(r.stall_count).is_equal(0)


# FT: FT-NET-037
func test_stalled_reader_gets_no_deltas_then_one_full() -> void:
	var r: NetResync = NetResync.new(15)
	_send(r, 1)
	r.on_ack(1)
	var seq: int = 2
	while _send(r, seq) == DELTA:
		seq += 1
	# Lag passed 15 unacknowledged snapshots: nothing more is sent.
	assert_bool(r.stalled).is_true()
	assert_int(r.last_sent_seq).is_equal(17)
	for i: int in range(60):
		seq += 1
		assert_int(_send(r, seq)).is_equal(NONE)
	assert_bool(r.holds_events()).is_true()
	# The client drains its backlog and acks the last snapshot sent.
	r.on_ack(17)
	seq += 1
	assert_int(r.decide(100)).is_equal(NONE)
	assert_int(_send(r, seq)).is_equal(FULL)
	# Deltas follow even before the full snapshot is acknowledged.
	for i: int in range(10):
		assert_int(_send(r, seq + 1 + i)).is_equal(DELTA)
	assert_int(r.last_full_seq).is_equal(seq)
	assert_int(r.stall_count).is_equal(1)
	assert_bool(r.holds_events()).is_false()


# FT: FT-NET-037
func test_send_error_or_queue_marks_stalled() -> void:
	var r: NetResync = NetResync.new(15)
	_send(r, 1)
	r.on_send_error()
	assert_int(r.decide(0)).is_equal(NONE)
	var s: NetResync = NetResync.new(15)
	_send(s, 1)
	assert_int(s.decide(NetResync.QUEUED_LIMIT)).is_equal(DELTA)
	assert_int(s.decide(NetResync.QUEUED_LIMIT + 1)).is_equal(NONE)


# FT: FT-NET-011
func test_inbox_orders_and_dedups() -> void:
	var inbox: NetEventInbox = NetEventInbox.new(10)
	assert_int(inbox.receive({"seq": 12}).size()).is_equal(0)
	assert_int(inbox.waiting()).is_equal(1)
	var out: Array[Dictionary] = inbox.receive({"seq": 11})
	assert_int(out.size()).is_equal(2)
	assert_int(out[1]["seq"]).is_equal(12)
	# The same events again inside a full snapshot are dropped as duplicates.
	assert_int(inbox.receive({"seq": 12}).size()).is_equal(0)
	assert_int(inbox.receive({"seq": 9}).size()).is_equal(0)
	assert_int(inbox.duplicates).is_equal(2)
	assert_int(inbox.last_seq).is_equal(12)


# FT: FT-NET-011, FT-NET-037
# The outbox numbers events per session, keeps every unacknowledged one, hands each to
# the connection once, and hands them all again to a new connection.
func test_outbox_keeps_events_until_acked() -> void:
	var box: NetEventOutbox = NetEventOutbox.new()
	for i: int in 5:
		assert_int(box.add(100 + i, "hit", {"i": i})).is_equal(i + 1)
	assert_int(box.take_unpushed().size()).is_equal(5)
	assert_int(box.take_unpushed().size()).is_equal(0)
	box.ack(3)
	assert_int(box.pending()).is_equal(2)
	box.add(200, "fired", {})
	var more: Array[PackedByteArray] = box.take_unpushed()
	assert_int(more.size()).is_equal(1)
	assert_int(NetProtocol.decode(more[0])["seq"]).is_equal(6)
	assert_int(NetProtocol.decode(more[0])["tick"]).is_equal(200)
	# A new connection gets everything not acknowledged, in order.
	box.restart()
	var again: Array[PackedByteArray] = box.take_unpushed()
	(
		assert_array(
			again.map(func(b: PackedByteArray) -> int: return NetProtocol.decode(b)["seq"])
		)
		. is_equal([4, 5, 6])
	)
	box.ack(99)
	assert_int(box.acked).is_equal(6)
	assert_int(box.pending()).is_equal(0)


func _session() -> NetSession:
	return NetSession.new(1, 60.0, 120.0)


func test_token_resumes_same_session_within_grace() -> void:
	var sessions: NetSessions = NetSessions.new(10_000_000)
	var s: NetSession = _session()
	s.conn = 3
	var token: String = sessions.issue(s)
	assert_int(token.length()).is_equal(32)
	assert_str(s.token).is_equal(token)
	sessions.drop(s, 1_000_000)
	assert_bool(s.connected()).is_false()
	assert_object(sessions.resume(token, 9_000_000)).is_same(s)
	assert_object(sessions.resume("nope", 9_000_000)).is_null()


# FT: FT-NET-033, FT-NET-026
# The grace runs on the caller's wall clock: the session lapses once, when it ends, and
# its token still resumes it afterwards (ServerSession then restores what is free).
func test_session_lapses_after_grace_and_token_still_resumes() -> void:
	var sessions: NetSessions = NetSessions.new(10_000_000)
	var s: NetSession = _session()
	var token: String = sessions.issue(s)
	sessions.drop(s, 1_000_000)
	assert_array(sessions.expire(5_000_000)).is_empty()
	assert_bool(s.lapsed).is_false()
	assert_array(sessions.expire(11_000_001)).is_equal([s])
	assert_bool(s.lapsed).is_true()
	assert_array(sessions.expire(12_000_000)).is_empty()
	assert_object(sessions.resume(token, 60_000_000)).is_same(s)
	# Presenting the token after the grace, before expire() ran, lapses it there.
	var t: NetSession = NetSession.new(2, 60.0, 120.0)
	var token_t: String = sessions.issue(t)
	sessions.drop(t, 1_000_000)
	assert_object(sessions.resume(token_t, 20_000_000)).is_same(t)
	assert_bool(t.lapsed).is_true()
	assert_array(sessions.expire(20_000_000)).is_empty()


func test_connected_token_is_taken_over() -> void:
	var sessions: NetSessions = NetSessions.new(10_000_000)
	var s: NetSession = _session()
	s.conn = 4
	var token: String = sessions.issue(s)
	# A restarted client presents the token before the old socket has closed: a
	# connected session never expires.
	assert_object(sessions.resume(token, 60_000_000)).is_same(s)
	assert_array(sessions.expire(60_000_000)).is_empty()


# FT: FT-NET-006
func test_token_bucket_limits_rate() -> void:
	var b: NetTokenBucket = NetTokenBucket.new(10.0, 5.0)
	var taken: int = 0
	for i: int in 20:
		if b.take(0):
			taken += 1
	assert_int(taken).is_equal(5)
	# 0.5 s refills 5 tokens.
	taken = 0
	for i: int in 20:
		if b.take(500_000):
			taken += 1
	assert_int(taken).is_equal(5)
	assert_bool(b.take(500_000)).is_false()
