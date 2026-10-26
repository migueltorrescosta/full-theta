extends GdUnitTestSuite
## The debrief (L3, FT-MIS-006, FT-MIS-010, FT-MIS-038, FT-PAIR-013, D35): after the outcome every
## pick on the ship gets `debrief` with the encounters (losses and fled apart), the director's
## decisions with reasons, the first use of each core action and the cooperative events per pair.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-MIS-038
func test_core_actions_are_data_and_first_use_times_them() -> void:
	var d: StationDef = StationViews.def("helm")
	assert_array(d.core_actions).contains(["face=helm_input.face", "jump=helm_jump"])
	assert_array(StationViews.def("tactical").core_actions).contains(["fire=fire|fire_guided"])
	var f: FirstUse = FirstUse.new()
	var still: HelmInputCommand = HelmInputCommand.new()
	f.on_command(0, still, 120)
	assert_float(f.for_ship(0)["helm"]["face"]).is_equal(-1.0)
	var face: HelmInputCommand = HelmInputCommand.new()
	face.face = true
	f.on_command(0, face, 300)
	f.on_command(0, face, 600)
	f.on_crew_op(0, "relay", "route_add", 900)
	var got: Dictionary = f.for_ship(0)
	assert_float(got["helm"]["face"]).is_equal(5.0)
	assert_float(got["relay"]["route"]).is_equal(15.0)
	assert_float(got["relay"]["mark"]).is_equal(-1.0)
	assert_float(f.for_ship(1)["helm"]["face"]).is_equal(-1.0)


# FT: FT-MIS-006, FT-MIS-010, FT-MIS-038, FT-PAIR-013
func test_debrief_record_of_a_finished_run() -> void:
	var w: SimWorld = ScenarioFixture.make().world
	var begin: BeginEncounterCommand = BeginEncounterCommand.new()
	begin.scenario_id = &"enemy_wave"
	begin.site = 0
	begin.ships = PackedInt32Array([0])
	w.submit(begin)
	w.step()
	var end: EndEncounterCommand = EndEncounterCommand.new()
	end.encounter = 0
	end.result = EncounterTable.Result.WON
	w.submit(end)
	w.step()
	var decision: DirectorDecision = DirectorDecision.new()
	decision.kind = DirectorDecision.Kind.PICK_ENCOUNTER
	decision.ship = 0
	decision.scenario_id = &"enemy_wave"
	decision.reason_key = "director.reason.budget_fits"
	var coop: CoopEvents = CoopEvents.new()
	coop.record(CoopEvents.SHORTCUT_SHARED, "p1", 0)
	var d: Dictionary = RunDebrief.new(w, [decision], coop, FirstUse.new()).for_ship(0)
	assert_int(d["encounters"].size()).is_equal(1)
	assert_str(d["encounters"][0]["result"]).is_equal("won")
	assert_bool(d["encounters"][0]["lost"]).is_false()
	assert_int(d["losses"]).is_equal(0)
	assert_int(d["fled"]).is_equal(0)
	assert_str(d["decisions"][0]["reason_key"]).is_equal("director.reason.budget_fits")
	assert_int(d["coop"][0]["events"]).is_equal(1)
	assert_float(d["first_use"]["helm"]["jump"]).is_equal(-1.0)
	# A lost encounter and a fled one are told apart (FT-MIS-010).
	w.encounters.losses_mask[0] = 1
	(
		assert_bool(
			RunDebrief.new(w, [], coop, FirstUse.new()).for_ship(0)["encounters"][0]["lost"]
		)
		. is_true()
	)
	assert_int(RunDebrief.new(w, [], coop, FirstUse.new()).for_ship(0)["losses"]).is_equal(1)
	w.encounters.losses_mask[0] = 0
	w.encounters.fled_mask[0] = 1
	var fled: Dictionary = RunDebrief.new(w, [], coop, FirstUse.new()).for_ship(0)
	assert_bool(fled["encounters"][0]["fled"]).is_true()
	assert_int(fled["losses"]).is_equal(0)
	assert_int(fled["fled"]).is_equal(1)


# FT: FT-MIS-038, FT-PAIR-013
# The server sends `debrief` right after `run_over`, with a Relay mark timed and a pair event
# counted.
func test_the_debrief_follows_the_outcome_card() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()
	crew[2].place_mark(-1, "", ENEMY, Vector3.ZERO)
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.session.crew.marks.marks_of(PLAYER).size() == 1
			)
		)
		. is_true()
	)
	server.session.coop.record(CoopEvents.SHORTCUT_SHARED, "p1", PLAYER)
	var from: int = h.mark(crew[0])
	var hit: SimHit = SimHit.new()
	hit.target_id = ENEMY
	hit.source_id = PLAYER
	DamageSystem.apply_hit(server.world, hit, 1.0e15)
	var e: Dictionary = await h.next_event(crew[0], NetProtocol.EVENT_DEBRIEF, from)
	assert_bool(e.is_empty()).is_false()
	var d: Dictionary = e["payload"]
	assert_int(d["ship"]).is_equal(PLAYER)
	assert_str(d["result"]).is_equal("win")
	assert_float(d["first_use"]["relay"]["mark"]).is_greater_equal(0.0)
	assert_int(d["coop"][0]["events"]).is_equal(1)
