extends GdUnitTestSuite
## S4 spike: resync policy, event inbox, session tokens and snapshot deltas
## (spike evidence for FT-NET-025, FT-NET-026, FT-NET-033 and FT-NET-037; the
## ids stay pending until T045 promotes the code).

const NONE: S4Resync.Action = S4Resync.Action.NONE
const DELTA: S4Resync.Action = S4Resync.Action.DELTA
const FULL: S4Resync.Action = S4Resync.Action.FULL


func _send(r: S4Resync, seq: int) -> S4Resync.Action:
	var action: S4Resync.Action = r.decide(0)
	if action != NONE:
		r.on_sent(seq, action == FULL)
	return action


func test_join_gets_full_then_deltas() -> void:
	var r: S4Resync = S4Resync.new(15)
	assert_int(_send(r, 1)).is_equal(FULL)
	assert_int(_send(r, 2)).is_equal(DELTA)
	assert_int(r.delta_base()).is_equal(1)
	r.on_ack(2)
	assert_int(r.delta_base()).is_equal(2)


func test_stalled_reader_gets_no_deltas_then_one_full() -> void:
	var r: S4Resync = S4Resync.new(15)
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
	assert_int(r.full_count).is_equal(2)
	assert_int(r.stall_count).is_equal(1)
	assert_bool(r.holds_events()).is_false()


func test_send_error_or_queue_marks_stalled() -> void:
	var r: S4Resync = S4Resync.new(15)
	_send(r, 1)
	r.on_send_error()
	assert_int(r.decide(0)).is_equal(NONE)
	var s: S4Resync = S4Resync.new(15)
	_send(s, 1)
	assert_int(s.decide(s.queued_limit)).is_equal(DELTA)
	assert_int(s.decide(s.queued_limit + 1)).is_equal(NONE)


func test_inbox_orders_and_dedups() -> void:
	var inbox: S4EventInbox = S4EventInbox.new(10)
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


func test_token_resumes_same_seat_within_grace() -> void:
	var sessions: S4Sessions = S4Sessions.new(10_000_000)
	var seat: Dictionary = {"ship": 2, "station": "helm"}
	var token: String = sessions.issue(seat, 5)
	assert_int(token.length()).is_equal(32)
	sessions.set_acked_event(token, 9)
	sessions.drop(token, 1_000_000)
	var back: Dictionary = sessions.resume(token, 9_000_000)
	assert_dict(back["seat"]).is_equal(seat)
	assert_int(back["acked_ev"]).is_equal(9)
	assert_bool(sessions.resume("nope", 9_000_000).is_empty()).is_true()


func test_token_expires_after_grace() -> void:
	var sessions: S4Sessions = S4Sessions.new(10_000_000)
	var token: String = sessions.issue({"ship": 0, "station": "relay"}, 0)
	sessions.drop(token, 1_000_000)
	assert_array(sessions.expire(5_000_000)).is_empty()
	assert_array(sessions.expire(11_000_001)).is_equal([token])
	assert_bool(sessions.resume(token, 11_000_002).is_empty()).is_true()


func test_snapshot_delta_round_trip() -> void:
	var base: Dictionary = {1: {"pos": Vector3.ZERO, "name": "a"}, 2: {"pos": Vector3.ONE}}
	var cur: Dictionary = {1: {"pos": Vector3(1, 0, 0), "name": "a"}, 3: {"pos": Vector3.UP}}
	var change: Dictionary = S4Snapshot.delta(base, cur)
	assert_dict(change["set"]).is_equal({1: {"pos": Vector3(1, 0, 0)}, 3: {"pos": Vector3.UP}})
	assert_array(change["gone"]).is_equal([2])
	assert_dict(S4Snapshot.apply(base, change)).is_equal(cur)
	assert_dict(base[1]).is_equal({"pos": Vector3.ZERO, "name": "a"})
