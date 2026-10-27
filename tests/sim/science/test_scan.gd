extends GdUnitTestSuite
## E01: the silhouette-alignment scan, verified on the server (FT-SCI-004, FT-SCI-011,
## FT-SCI-014 to FT-SCI-016) and the own-ship scan (FT-SCI-009).

const ME: int = 0
const FOE: int = 1


# FT: FT-SCI-004, FT-SCI-011
# A scan opens a session whose pose only the server knows; the exact angles score 1,
# wrong angles score low, and the result lands in KNOW as the scan confidence.
func test_server_verifies_the_submitted_pose() -> void:
	var w: SimWorld = ScienceFixture.world()
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceFixture.scan_cmd())
	assert_int(SimFixture.of_kind(events, &"scan_started").size()).is_equal(1)
	assert_int(w.science.kind[ME]).is_equal(ScienceTable.Session.SCAN)
	var truth: Vector3 = ScienceFixture.solution(w)
	var wrong: Vector3 = ScienceFixture.solution(w) + Vector3(1.5, 1.5, 1.5)
	var quality: float = ScanPuzzle.quality(
		w.science_def, w.science.puzzle_seed[ME], w.science.axes[ME], wrong
	)
	assert_float(quality).is_less(0.5)
	events = ScienceFixture.do(w, ScienceFixture.submit_cmd(truth))
	var done: SimEvent = SimFixture.of_kind(events, &"scan_done")[0]
	assert_float(done.vector.x).is_equal_approx(1.0, 1e-6)
	assert_int(w.science.kind[ME]).is_equal(ScienceTable.Session.NONE)
	assert_float(ScienceKnowledge.confidence(w, 1, FOE)).is_equal_approx(done.value, 1e-9)
	assert_float(done.value).is_greater(0.8)


# FT: FT-SCI-011
# A submit with no open scan, and a second scan while one is open, are refused.
func test_one_session_at_a_time_and_no_free_submit() -> void:
	var w: SimWorld = ScienceFixture.world()
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceFixture.submit_cmd(Vector3.ZERO))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("no_session")
	ScienceFixture.do(w, ScienceFixture.scan_cmd())
	events = ScienceFixture.do(w, ScienceFixture.scan_cmd())
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("busy")
	events = ScienceFixture.do(w, ScienceFixture.hack_cmd(&"engines"))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("busy")


# FT: FT-SCI-011
# Own ships, unknown ships and contacts beyond sensor range cannot be scanned.
func test_scan_targets_are_checked() -> void:
	var w: SimWorld = ScienceFixture.world()
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceFixture.scan_cmd(ME))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("bad_contact")
	events = ScienceFixture.do(w, ScienceFixture.scan_cmd(9))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("bad_contact")
	var far: SimWorld = ScienceFixture.world(25000.0)
	events = ScienceFixture.do(far, ScienceFixture.scan_cmd())
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("not_detected")
	# Probe coverage lets the scan reach beyond the ship's own range (P13).
	far = ScienceFixture.world(19000.0)
	far.science_def = far.science_def.duplicate()
	far.science_def.scan_range_factor = 0.5
	events = ScienceFixture.do(far, ScienceFixture.scan_cmd())
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("out_of_range")
	ScienceFixture.cover(far)
	events = ScienceFixture.do(far, ScienceFixture.scan_cmd())
	assert_int(SimFixture.of_kind(events, &"scan_started").size()).is_equal(1)


# FT: FT-SCI-014
# The rotation axes grow with the noise from 1 to 3.
func test_axes_grow_with_noise() -> void:
	var def: ScienceDef = ScienceFixture.science()
	assert_int(ScienceNoise.axes_for(def, 0.0, false)).is_equal(1)
	assert_int(ScienceNoise.axes_for(def, def.axes_noise_steps[0], false)).is_equal(2)
	assert_int(ScienceNoise.axes_for(def, def.axes_noise_steps[1], false)).is_equal(3)
	assert_int(ScienceNoise.axes_for(def, 1.0, false)).is_equal(3)
	# And in a live scan: near and broadside is clean, far and bow-on is noisy.
	var clean: SimWorld = ScienceFixture.world(2000.0, true)
	ScienceFixture.do(clean, ScienceFixture.scan_cmd())
	assert_int(_open_axes(clean)).is_equal(1)
	var noisy: SimWorld = ScienceFixture.world(18000.0, false)
	ScienceFixture.do(noisy, ScienceFixture.scan_cmd())
	assert_int(_open_axes(noisy)).is_equal(3)


# FT: FT-SCI-015
# A class fully scanned this run starts later scans pre-aligned on two axes.
func test_fully_scanned_class_starts_pre_aligned() -> void:
	var w: SimWorld = ScienceFixture.world(18000.0, false)
	ScienceFixture.do(w, ScienceFixture.scan_cmd())
	assert_int(_open_axes(w)).is_equal(3)
	ScienceFixture.do(w, ScienceFixture.submit_cmd(ScienceFixture.solution(w)))
	assert_bool(ScienceKnowledge.class_fully_scanned(w, 1, FOE)).is_true()
	# A second raider of the same class, scanned for the first time, starts pre-aligned.
	var other: int = w.spawn_ship(TestDefs.raider(), 2, Vector3(0, 0, -18000), Quaternion.IDENTITY)
	w.step()
	ScienceFixture.do(w, ScienceFixture.scan_cmd(other))
	assert_int(_open_axes(w)).is_equal(1)
	assert_float(w.science.noise[ME]).is_greater(w.science_def.axes_noise_steps[1])


# FT: FT-SCI-016
# Match quality above the lock threshold raises the confidence of the result.
func test_lock_raises_confidence() -> void:
	var def: ScienceDef = ScienceFixture.science()
	var below: float = ScanPuzzle.confidence(def, def.lock_threshold - 0.001, 0.3)
	var at: float = ScanPuzzle.confidence(def, def.lock_threshold, 0.3)
	assert_float(at - below).is_greater(def.lock_bonus * 0.9)
	assert_float(ScanPuzzle.confidence(def, 1.0, 0.0)).is_equal(1.0)
	assert_float(ScanPuzzle.confidence(def, 0.0, 0.0)).is_equal(0.0)
	# In a live scan the lock is reported and a worse match locks less.
	var w: SimWorld = ScienceFixture.world()
	var locked: SimEvent = ScienceFixture.scan_exactly(w)
	assert_str(locked.tag).is_equal("locked")
	var v: SimWorld = ScienceFixture.world()
	ScienceFixture.do(v, ScienceFixture.scan_cmd())
	var off: Vector3 = ScienceFixture.solution(v) + Vector3(0.7, 0.7, 0.7)
	var events: Array[SimEvent] = ScienceFixture.do(v, ScienceFixture.submit_cmd(off))
	var bad: SimEvent = SimFixture.of_kind(events, &"scan_done")[0]
	assert_str(bad.tag).is_equal("")
	assert_float(bad.value).is_less(locked.value)


# FT: FT-SCI-005, FT-PAIR-003
# P3: a scan at the scan-position mark has less noise, so it gets a denser cloud and a
# higher confidence than the same scan off the mark; an off-aspect scan still completes
# inside the time cap.
func test_scan_at_the_mark_is_cleaner() -> void:
	var off: SimWorld = ScienceFixture.world(8000.0, false)
	ScienceFixture.do(off, ScienceFixture.scan_cmd())
	var off_noise: float = off.science.noise[ME]
	var at: SimWorld = ScienceFixture.world(8000.0, false)
	var mark: ScienceMarkCommand = ScienceMarkCommand.new()
	mark.contact = FOE
	ScienceFixture.do(at, mark)
	var t: ScienceTable = at.science
	at.kin.place(ME, t.mark_x[ME], t.mark_y[ME], t.mark_z[ME])
	ScienceFixture.do(at, ScienceFixture.scan_cmd())
	assert_float(t.noise[ME]).is_less(off_noise)
	var def: ScienceDef = at.science_def
	var cloud_at: int = ScanPuzzle.cloud(def, t.puzzle_seed[ME], t.noise[ME], t.axes[ME]).size()
	var cloud_off: int = (
		ScanPuzzle.cloud(def, off.science.puzzle_seed[ME], off_noise, off.science.axes[ME]).size()
	)
	assert_int(cloud_off).is_greater_equal(cloud_at)
	assert_float(ScanPuzzle.confidence(def, 0.9, t.noise[ME])).is_greater(
		ScanPuzzle.confidence(def, 0.9, off_noise)
	)
	# The scan left open past the cap fails with a timeout, nothing recorded.
	var events: Array[SimEvent] = SimFixture.run(off, int(def.scan_cap_s * 60.0) + 2)
	assert_str(SimFixture.of_kind(events, &"scan_failed")[0].tag).is_equal("timeout")
	assert_float(ScienceKnowledge.confidence(off, 1, FOE)).is_equal(0.0)


# FT: FT-SCI-011
# The same seed and commands give the same state hash and the same cloud (replay).
func test_scan_is_deterministic() -> void:
	var hashes: Array[String] = []
	var clouds: Array[PackedVector3Array] = []
	for i: int in 2:
		var w: SimWorld = ScienceFixture.world()
		ScienceFixture.do(w, ScienceFixture.scan_cmd())
		clouds.append(
			ScanPuzzle.cloud(
				w.science_def, w.science.puzzle_seed[ME], w.science.noise[ME], w.science.axes[ME]
			)
		)
		SimFixture.run(w, 30)
		hashes.append(w.state_hash())
	assert_str(hashes[0]).is_equal(hashes[1])
	assert_array(clouds[0]).is_equal(clouds[1])


# FT: FT-SCI-011
# Cancel closes a session without a result; losing the contact fails it.
func test_cancel_and_lost_contact() -> void:
	var w: SimWorld = ScienceFixture.world()
	ScienceFixture.do(w, ScienceFixture.scan_cmd())
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceCancelCommand.new())
	assert_str(SimFixture.of_kind(events, &"scan_failed")[0].tag).is_equal("cancelled")
	assert_int(w.science.kind[ME]).is_equal(ScienceTable.Session.NONE)
	ScienceFixture.do(w, ScienceFixture.scan_cmd())
	w.kin.place(FOE, 0.0, 0.0, -60000.0)
	events = SimFixture.run(w, 2)
	assert_str(SimFixture.of_kind(events, &"scan_failed")[0].tag).is_equal("lost")


# FT: FT-SCI-009, FT-PAIR-003
# P10: the own-ship scan takes self_scan_s, then marks the ship as self-scanned (the
# seam that reveals fault causes); a second scan can't start meanwhile.
func test_own_ship_scan() -> void:
	var w: SimWorld = ScienceFixture.world()
	assert_bool(w.science.self_scanned[ME] >= 0).is_false()
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceSelfScanCommand.new())
	assert_int(SimFixture.of_kind(events, &"self_scan_started").size()).is_equal(1)
	events = ScienceFixture.do(w, ScienceFixture.scan_cmd())
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("busy")
	events = SimFixture.run(w, int(w.science_def.self_scan_s * 60.0) + 2)
	assert_int(SimFixture.of_kind(events, &"self_scan_done").size()).is_equal(1)
	assert_bool(w.science.self_scanned[ME] >= 0).is_true()
	assert_int(w.science.kind[ME]).is_equal(ScienceTable.Session.NONE)


func _open_axes(w: SimWorld) -> int:
	var mask: int = w.science.axes[ME]
	return (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1)
