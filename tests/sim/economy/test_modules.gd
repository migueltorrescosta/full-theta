extends GdUnitTestSuite
## Slot modules: fitting changes a private copy of the ship's definition by the
## module's trade-off, a full slot sells its old module in the same trade, builds differ,
## and the shared definitions are never touched (FT-ARC-020).

const SITE: int = StoryFixture.SITE

var _held: Dictionary[String, Resource] = {}


func before_test() -> void:
	_held = TestDefs.all_defs()


func _module(id: StringName) -> ModuleDef:
	return load("res://content/modules/%s.tres" % id) as ModuleDef


## A docked world: the corvette (engine and utility slot) with 5000 credits and Kappa's card.
func _docked() -> Array:
	var w: SimWorld = StoryFixture.world()
	StoryFixture.spawn(w, TestDefs.corvette(), StoryFixture.BLUE)
	w.economy.credits[0] = 5000
	StoryFixture.dock(w, 0)
	return [w, StoryFixture.post(w, 0, StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE))]


func _buy(w: SimWorld, card: int, module: StringName, slot: int) -> bool:
	var c: BuyModuleCommand = BuyModuleCommand.new()
	c.card = card
	c.module_key = module
	c.slot = slot
	return StoryFixture.run(w, 0, c)


func _why(w: SimWorld) -> String:
	var refused: Array[SimEvent] = StoryFixture.events(w, &"trade_refused")
	return String(refused[-1].tag) if not refused.is_empty() else ""


# FT: FT-MIS-035, FT-DAT-014
# Fitting applies the module's gains and its costs to the ship's effective definition and
# leaves the base definition exactly as loaded.
func test_trade_off_deltas() -> void:
	var w: SimWorld = _docked()[0]
	var base: ShipDef = TestDefs.corvette()
	var before: String = TestDefs.def_hash(base)
	assert_bool(ModuleSystem.fit(w, 0, 0, _module(&"hx2_afterburner"))).is_true()
	var fitted: ShipDef = w.defs[0]
	assert_object(fitted).is_not_same(base)
	assert_object(w.base_defs[0]).is_same(base)
	assert_float(fitted.max_thrust_pos.z).is_equal_approx(base.max_thrust_pos.z * 1.25, 0.01)
	assert_float(fitted.max_thrust_neg.z).is_equal_approx(base.max_thrust_neg.z * 1.25, 0.01)
	for i: int in base.subsystems.size():
		assert_float(fitted.subsystems[i].fault_heat_threshold).is_equal_approx(
			base.subsystems[i].fault_heat_threshold * 0.85, 0.001
		)
	assert_float(fitted.power.reactor_output).is_equal(base.power.reactor_output)
	assert_str(TestDefs.def_hash(base)).is_equal(before)
	ModuleSystem.fit(w, 0, 1, _module(&"lx1_longscan"))
	assert_float(w.defs[0].sensor_range).is_equal_approx(base.sensor_range * 1.3, 0.01)
	assert_float(w.defs[0].power.reactor_output).is_equal_approx(
		base.power.reactor_output * 0.9, 0.01
	)
	assert_float(w.defs[0].max_thrust_pos.z).is_equal_approx(base.max_thrust_pos.z * 1.25, 0.01)
	assert_str(TestDefs.def_hash(base)).is_equal(before)
	assert_float(base.power.reactor_output).is_greater(0.0)


# FT: FT-MIS-036, FT-COM-009
# Buying fits the module at once for the market's price; a module of another slot type or
# a slot that doesn't exist is refused, as is a purchase the credits don't cover.
func test_buying_a_module() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	assert_bool(_buy(w, card, &"hx2_afterburner", 0)).is_true()
	assert_int(w.economy.credits[0]).is_equal(4100)
	assert_object(ModuleSystem.fitted(w, 0, 0)).is_same(_module(&"hx2_afterburner"))
	assert_float(w.defs[0].max_thrust_pos.z).is_greater(TestDefs.corvette().max_thrust_pos.z)
	(
		assert_array(
			StoryFixture.events(w, &"module_fitted").map(func(e: SimEvent) -> String: return e.tag)
		)
		. is_equal(["hx2_afterburner"])
	)
	assert_bool(_buy(w, card, &"lx1_longscan", 0)).is_false()
	assert_str(_why(w)).is_equal("wrong_slot")
	assert_bool(_buy(w, card, &"lx1_longscan", 5)).is_false()
	assert_str(_why(w)).is_equal("bad_item")
	assert_bool(_buy(w, card, &"no_such_module", 1)).is_false()
	w.economy.credits[0] = 100
	assert_bool(_buy(w, card, &"lx1_longscan", 1)).is_false()
	assert_str(_why(w)).is_equal("no_credits")
	assert_int(w.economy.credits[0]).is_equal(100)
	assert_object(ModuleSystem.fitted(w, 0, 1)).is_null()
	StoryFixture.dock(w, 0, 9)
	assert_bool(_buy(w, card, &"lx1_longscan", 1)).is_false()
	assert_str(_why(w)).is_equal("not_docked")


# FT: FT-MIS-036, FT-COM-009
# Buying for a full slot sells the old module in the same command: its sale price comes
# off the cost, only the new module's trade-off remains, and the sale is reported.
func test_full_slot_sells_the_old_module() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	assert_bool(_buy(w, card, &"hx2_afterburner", 0)).is_true()
	w.drain_events()
	assert_bool(_buy(w, card, &"bx3_reactor", 0)).is_true()
	# 900 for the first, then 1200 less half of 900 for the swap.
	assert_int(w.economy.credits[0]).is_equal(5000 - 900 - (1200 - 450))
	assert_object(ModuleSystem.fitted(w, 0, 0)).is_same(_module(&"bx3_reactor"))
	var events: Array[SimEvent] = w.drain_events()
	var sold: Array[SimEvent] = SimFixture.of_kind(events, &"module_sold")
	assert_int(sold.size()).is_equal(1)
	assert_str(sold[0].tag).is_equal("hx2_afterburner")
	assert_float(sold[0].value).is_equal(450.0)
	var base: ShipDef = TestDefs.corvette()
	assert_float(w.defs[0].max_thrust_pos.z).is_equal(base.max_thrust_pos.z)
	assert_float(w.defs[0].power.reactor_output).is_equal_approx(
		base.power.reactor_output * 1.2, 0.01
	)
	assert_float(w.defs[0].mass).is_equal_approx(base.mass * 1.1, 0.01)
	# A sale alone empties the slot at the market's rate.
	var sell: SellModuleCommand = SellModuleCommand.new()
	sell.card = card
	sell.slot = 0
	assert_bool(StoryFixture.run(w, 0, sell)).is_true()
	assert_int(w.economy.credits[0]).is_equal(5000 - 900 - 750 + 600)
	assert_object(ModuleSystem.fitted(w, 0, 0)).is_null()
	assert_object(w.defs[0]).is_same(base)
	assert_bool(StoryFixture.run(w, 0, sell)).is_false()


# FT: FT-MIS-022
# Different purchases make distinct builds: the effective definitions differ, and so
# does the state hash of otherwise identical worlds.
func test_distinct_builds() -> void:
	var worlds: Array[SimWorld] = []
	var cards: Array[int] = []
	for module: StringName in [&"hx2_afterburner", &"bx3_reactor", &""]:
		var d: Array = _docked()
		worlds.append(d[0])
		cards.append(d[1])
		if module != &"":
			assert_bool(_buy(d[0], d[1], module, 0)).is_true()
			d[0].economy.credits[0] = 5000
	assert_bool(worlds[0].defs[0].max_thrust_pos != worlds[1].defs[0].max_thrust_pos).is_true()
	(
		assert_bool(
			worlds[0].defs[0].power.reactor_output != worlds[1].defs[0].power.reactor_output
		)
		. is_true()
	)
	var hashes: Dictionary = {}
	for w: SimWorld in worlds:
		hashes[w.state_hash()] = true
	assert_int(hashes.size()).is_equal(3)


# FT: FT-MIS-017, FT-MIS-011
# A ship reset drops its modules and restores the base definition; the shared base is
# unchanged.
func test_reset_restores_the_base_build() -> void:
	var w: SimWorld = _docked()[0]
	ModuleSystem.fit(w, 0, 0, _module(&"bx3_reactor"))
	assert_object(w.defs[0]).is_not_same(w.base_defs[0])
	StoryFixture.reset(w, 0)
	assert_object(w.defs[0]).is_same(w.base_defs[0])
	assert_object(ModuleSystem.fitted(w, 0, 0)).is_null()
	assert_array(Array(w.modules.module_ix)).is_equal([-1, -1])


# FT: FT-DAT-014, FT-MIS-035
# Ships declare slots and modules a trade-off: a module with only gains, an unknown stat
# or the wrong slot count fails validation.
func test_module_and_slot_validation() -> void:
	assert_array(TestDefs.corvette().validate()).is_empty()
	for id: StringName in [&"hx2_afterburner", &"bx3_reactor", &"lx1_longscan"]:
		assert_array(_module(id).validate()).is_empty()
	var free_lunch: ModuleDef = _module(&"hx2_afterburner").duplicate()
	free_lunch.deltas = {&"thrust": 0.2, &"sensor_range": 0.1}
	assert_array(free_lunch.validate()).contains_exactly(
		["deltas: needs at least one gain and one cost (a trade-off, FT-MIS-035)"]
	)
	free_lunch.deltas = {&"warp": 0.2, &"thrust": -0.1}
	assert_bool("\n".join(free_lunch.validate()).contains("unknown stat warp")).is_true()
	var ship: ShipDef = TestDefs.corvette().duplicate()
	var none: SlotDef = SlotDef.new()
	none.slot_type = &"engine"
	ship.slots = [none, none]
	var errors: String = "\n".join(ship.validate())
	assert_str(errors).contains("slots[0].count: must be in [1.0, 8.0]")
	assert_str(errors).contains("slots[1].slot_type: duplicate engine")


## Speed after `ticks` ticks of full throttle for a ship fitted with the module (or none).
func _speed_after(module: StringName, ticks: int) -> float:
	var w: SimWorld = _docked()[0]
	if module != &"":
		ModuleSystem.fit(w, 0, 0, _module(module))
	w.helm.docked_site[0] = -1
	var c: HelmInputCommand = HelmInputCommand.new()
	c.throttle = 1.0
	StoryFixture.run(w, 0, c)
	for i: int in ticks:
		w.step()
	return w.kin.vel[0].length()


# FT: FT-MIS-035
# A module's thrust and mass deltas reach flight, not only the effective definition: the
# afterburner raises the kinematics thrust limit and the reactor's mass cost applies.
func test_module_deltas_reach_flight() -> void:
	var w: SimWorld = _docked()[0]
	var base_mass: float = w.kin.mass[0]
	var base_inertia: Vector3 = w.kin.inertia[0]
	var base_thrust: float = w.kin.max_thrust_pos[0].z
	ModuleSystem.fit(w, 0, 0, _module(&"hx2_afterburner"))
	assert_float(w.kin.max_thrust_pos[0].z).is_equal_approx(base_thrust * 1.25, 0.01)
	ModuleSystem.fit(w, 0, 0, _module(&"bx3_reactor"))
	assert_float(w.kin.mass[0]).is_equal_approx(base_mass * 1.1, 0.01)
	# Inertia scales with the same mass delta (review 2 L4), so a heavy module slows turning.
	assert_vector(w.kin.inertia[0]).is_equal_approx(base_inertia * 1.1, base_inertia * 0.001)
	assert_float(w.kin.max_thrust_pos[0].z).is_equal_approx(base_thrust, 0.01)
	ModuleSystem.fit(w, 0, 0, null)
	assert_float(w.kin.mass[0]).is_equal(base_mass)
	assert_vector(w.kin.inertia[0]).is_equal(base_inertia)
	assert_float(_speed_after(&"hx2_afterburner", 30)).is_greater(_speed_after(&"", 30))
