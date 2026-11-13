extends GdUnitTestSuite
## Fail-forward and the run economy (#38 D4, D7): the paid co-op relaunch (gp-10, amends
## D259), a raider's bounty, a wreck's salvage and the run modifier's numbers (gp-11), in the
## server's own m3_run world (FleetFixture).

static var _defs: DefLibrary = DefLibrary.new()


static func of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


static func relaunch(f: FleetFixture, ship: int) -> RelaunchShipCommand:
	var c: RelaunchShipCommand = RelaunchShipCommand.new()
	c.ship = ship
	f.world.submit(c)
	return c


## A raider `distance` m off ship 0's bow (out of its fight: AI off).
static func raider_near(f: FleetFixture, distance: float) -> int:
	var w: SimWorld = f.world
	var at: PackedFloat64Array = CubePoint.plus(w.kin.point(0), Vector3(0.0, 0.0, -distance))
	var id: int = w.spawn_npc(_defs.npc(&"m1_raider"), Factions.RAIDER, at)
	w.ai.enabled[id] = 1
	return id


# FT: FT-MIS-051, FT-MIS-011
func test_a_coop_ship_relaunches_once_for_its_price() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	var def: RunDef = w.run_def
	assert_int(RelaunchShipCommand.cost(w)).is_equal(def.relaunch_cost)
	Economy.add_credits(w, 0, 1000)
	DamageSystem.damage_hull(w, 0, INF, -1)
	var gone: Array[SimEvent] = of_kind(f.step(1), GameOutcome.EVENT_ELIMINATED)
	assert_int(int(gone[0].value)).is_equal(1)
	assert_bool(f.outcome().over()).is_false()
	var c: RelaunchShipCommand = relaunch(f, 0)
	f.step(1)
	assert_bool(c.accepted).is_true()
	# The fresh ship keeps the rest of its purse, not the starting one.
	assert_int(Economy.credits(w, 0)).is_equal(def.start_credits + 1000 - def.relaunch_cost)
	assert_int(w.ships.relaunches[0]).is_equal(1)
	DamageSystem.damage_hull(w, 0, INF, -1)
	Economy.add_credits(w, 0, 5000)
	gone = of_kind(f.step(1), GameOutcome.EVENT_ELIMINATED)
	assert_int(int(gone[0].value)).is_equal(0)
	var again: RelaunchShipCommand = relaunch(f, 0)
	f.step(1)
	assert_bool(again.accepted).is_false()
	assert_int(f.outcome().reason).is_equal(GameOutcome.Reason.ALL_LOST)


# FT: FT-MIS-051
func test_a_purse_short_of_the_price_has_no_relaunch() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	assert_int(Economy.credits(w, 0)).is_less(w.run_def.relaunch_cost)
	DamageSystem.damage_hull(w, 0, INF, -1)
	var gone: Array[SimEvent] = of_kind(f.step(1), GameOutcome.EVENT_ELIMINATED)
	# The event keeps the policy's lives and carries the purse: the client shows the relaunch disabled.
	assert_int(int(gone[0].value)).is_equal(1)
	assert_int(gone[0].other_id).is_equal(Economy.credits(w, 0))
	assert_int(f.outcome().reason).is_equal(GameOutcome.Reason.ALL_LOST)
	var c: RelaunchShipCommand = relaunch(f, 0)
	f.step(1)
	assert_bool(c.accepted).is_false()
	assert_int(w.ships.status[0]).is_equal(ShipStateTable.Status.DESTROYED)


# FT: FT-MIS-051
func test_other_modes_relaunch_free() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.HOLDOUT, 2)
	assert_int(RelaunchShipCommand.cost(f.world)).is_equal(0)


# FT: FT-MIS-052, FT-MIS-021
func test_a_raider_kill_pays_the_bounty_and_its_wreck_salvage_nearby() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	var def: RunDef = w.run_def
	var credits: int = Economy.credits(w, 0)
	var raider: int = raider_near(f, 200.0)
	f.step(1)
	DamageSystem.damage_hull(w, raider, INF, 0)
	var events: Array[SimEvent] = f.step(1)
	var bounty: Array[SimEvent] = of_kind(events, &"bounty")
	assert_array(bounty).has_size(1)
	assert_int(bounty[0].ship_id).is_equal(0)
	assert_int(bounty[0].other_id).is_equal(raider)
	assert_int(int(bounty[0].value)).is_equal(def.bounty)
	# The wreck is 200 m off, inside salvage_range: collected the same tick, once.
	var salvage: Array[SimEvent] = of_kind(events, &"salvage")
	assert_array(salvage).has_size(1)
	assert_int(int(salvage[0].value)).is_equal(def.salvage)
	assert_array(of_kind(f.step(60), &"salvage")).is_empty()
	assert_int(Economy.credits(w, 0)).is_equal(credits + def.bounty + def.salvage)


# FT: FT-MIS-052
func test_a_far_wreck_waits_for_a_ship_within_range() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	var raider: int = raider_near(f, 2000.0)
	f.step(1)
	var wreck_at: PackedFloat64Array = w.kin.point(raider)
	DamageSystem.damage_hull(w, raider, INF, 0)
	assert_array(of_kind(f.step(5), &"salvage")).is_empty()
	w.kin.place(0, CubePoint.plus(wreck_at, Vector3(250.0, 0.0, 0.0)))
	var salvage: Array[SimEvent] = of_kind(f.step(2), &"salvage")
	assert_array(salvage).has_size(1)
	assert_int(salvage[0].ship_id).is_equal(0)
	assert_int(w.wrecks.taken_by[0]).is_equal(0)


# FT: FT-MIS-052
func test_a_retreated_raider_pays_nothing() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	var raider: int = raider_near(f, 150000.0)
	# Under its retreat hull fraction, so the AI flees; nobody detects it that far out.
	w.damage.health[w.damage.hull_row(raider)] = 0.2 * w.defs[raider].hull_max
	var events: Array[SimEvent] = f.step(3)
	assert_int(w.ships.status[raider]).is_equal(ShipStateTable.Status.RETREATED)
	assert_array(of_kind(events, &"bounty")).is_empty()
	assert_int(w.wrecks.size()).is_equal(0)


# FT: FT-MIS-052
func test_a_raider_lost_to_no_crew_pays_no_bounty() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 1)
	var w: SimWorld = f.world
	var raider: int = raider_near(f, 5000.0)
	f.step(1)
	DamageSystem.damage_hull(w, raider, INF, -1)
	var events: Array[SimEvent] = f.step(1)
	assert_array(of_kind(events, &"bounty")).is_empty()
	assert_int(w.wrecks.size()).is_equal(1)


# FT: FT-MIS-053
func test_the_rolled_modifier_scales_the_run_numbers() -> void:
	var main: ServerMain = ServerMain.new()
	var setup: RunSetup = main.run_setup(_defs)
	assert_int(setup.modifiers.size()).is_equal(3)
	setup.rules.modifier_id = &"lean_times"
	var w: SimWorld = setup.build()
	var api: ScenarioApi = ScenarioApi.new(w)
	assert_float(api.modifier_strength()).is_equal(1.0)
	# Kappa's parts at 25 credits, times 1.25, rounded up; the content def stays as it was.
	assert_int(w.markets[&"kappa"].prices[&"parts"]).is_equal(32)
	assert_int(setup.markets[&"kappa"].prices[&"parts"]).is_equal(25)
	assert_int(SalvageSystem.scaled(w.run_def.bounty, w.modifier.bounty)).is_equal(150)
	setup.rules.modifier_id = &"rich_pickings"
	w = setup.build()
	assert_float(ScenarioApi.new(w).modifier_strength()).is_equal_approx(1.1, 1e-9)
	assert_int(SalvageSystem.scaled(w.run_def.salvage, w.modifier.salvage)).is_equal(300)
	assert_int(w.markets[&"kappa"].prices[&"parts"]).is_equal(25)


# FT: FT-MIS-053
func test_no_modifier_changes_nothing() -> void:
	var main: ServerMain = ServerMain.new()
	var setup: RunSetup = main.run_setup(_defs)
	var w: SimWorld = setup.build()
	assert_float(ScenarioApi.new(w).modifier_strength()).is_equal(1.0)
	assert_bool(w.markets[&"kappa"] == setup.markets[&"kappa"]).is_true()
	for m: RunModifierDef in _defs.run_modifiers():
		assert_array(m.validate()).is_empty()


# FT: FT-MIS-053
# The prices modifier scales module prices too (buy, trade-in and Comms' rows read one price).
func test_the_prices_modifier_scales_module_prices() -> void:
	var main: ServerMain = ServerMain.new()
	var setup: RunSetup = main.run_setup(_defs)
	setup.rules.modifier_id = &"lean_times"
	var w: SimWorld = setup.build()
	var module: ModuleDef = w.module_defs[ModuleSystem.index_of(w, &"lx1_longscan")]
	assert_int(Trade.module_price(w, module)).is_equal(750)
	setup.rules.modifier_id = &""
	assert_int(Trade.module_price(setup.build(), module)).is_equal(module.price)
