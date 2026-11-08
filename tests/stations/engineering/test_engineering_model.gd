extends GdUnitTestSuite
## EngineeringModel (R13-6) without a scene: the block readers, the actions' sends and
## refusals, the pending values and the faults and repair lists, on the station fixture's
## context (m1_corvette, the fixture's ENGINEERING block).

const KIND = SubsystemDef.Kind

var _toasts: Array[String] = []


func before() -> void:
	I18n.apply("en")


func _model() -> EngineeringModel:
	_toasts = []
	var ctx: StationContext = StationFixture.context("engineering")
	ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: _toasts.append(key))
	return EngineeringModel.new(ctx, ctx.ship_def())


func _commands(m: EngineeringModel) -> Array:
	return StationFixture.sent(m.ctx).of("command").map(
		func(c: Array) -> Dictionary: return c[1][0]
	)


# FT: FT-ENG-002
func test_pips_send_show_pending_and_respect_the_limits() -> void:
	var m: EngineeringModel = _model()
	assert_int(m.count()).is_equal(6)
	assert_int(m.pips_used()).is_equal(10)
	assert_bool(m.set_pips(1, 3)).is_true()
	assert_dict(_commands(m)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.THRUSTERS, "pips": 3}
	)
	# The sent value shows until the snapshot agrees or PENDING_MS passes.
	assert_int(m.pips_of(1)).is_equal(3)
	StationFixture.clock(m.ctx).ms += EngineeringModel.PENDING_MS + 1
	assert_int(m.pips_of(1)).is_equal(2)
	# The reactor takes none, with its toast; over the cap the request goes to the server,
	# whose refusal is the toast (F5, R12-7).
	assert_bool(m.set_pips(5, 1)).is_false()
	m.ctx.view.blocks[StationViews.Section.STATUS]["pip_cap"] = 10
	assert_bool(m.set_pips(2, 3)).is_true()
	assert_array(_toasts).is_equal(["toast.eng_reactor"])
	assert_int(_commands(m).size()).is_equal(2)


# FT: FT-ENG-003
func test_tightness_snaps_to_steps_within_the_range() -> void:
	var m: EngineeringModel = _model()
	assert_float(m.tightness()).is_equal(1.5)
	assert_float(m.shield_frac()).is_equal_approx(0.7, 1e-6)
	assert_bool(m.set_tightness(1.9)).is_true()
	assert_dict(_commands(m)[-1]).is_equal({"kind": "set_shield", "power": -1, "tightness": 2.0})
	assert_bool(m.set_tightness(2.1)).is_false()


# FT: FT-ENG-004
func test_dispatch_and_recall_pick_the_crew() -> void:
	var m: EngineeringModel = _model()
	# Crew A works on the engines (the fixture's crews bitmask); B is idle.
	assert_int(m.crew_job(0)).is_equal(0)
	assert_int(m.crew_job(1)).is_equal(-1)
	assert_bool(m.dispatch(1, 1)).is_false()
	assert_array(_toasts).is_equal(["toast.eng_whole"])
	assert_bool(m.select(2)).is_true()
	assert_bool(m.dispatch_nearest()).is_true()
	assert_dict(_commands(m)[-1]).is_equal(
		{"kind": "dispatch_repair", "crew": 1, "subsystem_id": "weapons"}
	)
	assert_int(m.crew_pick).is_equal(1)
	assert_bool(m.recall(0)).is_true()
	assert_dict(_commands(m)[-1]).is_equal({"kind": "recall_repair", "crew": 0})
	assert_int(m.crew_pick).is_equal(0)


# FT: FT-ENG-005
func test_fault_and_queue_lines_worst_first() -> void:
	var m: EngineeringModel = _model()
	var faults: Array = m.fault_lines()
	(
		assert_array(faults.map(func(l: Array) -> String: return l[1]))
		. is_equal(["warn", "warn", "warn"])
	)
	assert_str(faults[0][0]).contains("40%")
	assert_str(EngineeringModel.severity_glyph("danger_text")).is_equal("!! ")
	var queue: Array = m.queue_lines().map(func(l: Array) -> String: return l[0])
	assert_str(queue[0]).is_equal("1. %s 40%%  A" % m.short_name(0))
	assert_str(queue[1]).is_equal("2. %s 75%%  %s" % [m.short_name(2), tr("eng.waiting")])
	# A heat fault event on the own ship lists the part as overheated, first.
	m.on_sim_event(&"fault", {"ship": StationFixture.SHIP, "tag": "sensors"})
	assert_str(m.fault_lines()[0][1]).is_equal("danger_text")


# FT: FT-ENG-001
func test_hits_on_the_own_ship_fade() -> void:
	var m: EngineeringModel = _model()
	m.on_sim_event(&"hit", {"ship": StationFixture.SHIP, "vector": Vector3(0, 1, 16)})
	m.on_sim_event(&"hit", {"ship": 2, "vector": Vector3(0, 0, -10)})
	assert_int(m.hits.size()).is_equal(1)
	StationFixture.clock(m.ctx).ms += EngineeringModel.HIT_MS + 1
	m.expire_hits()
	assert_array(m.hits).is_empty()
