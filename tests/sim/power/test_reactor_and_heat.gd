extends GdUnitTestSuite
## Review 2026-11-08 A1 and A5 (R09-1, R16-1, R16-3): the reactor's health scales its
## output and the pips it can feed, the weapons' health scales the weapon charge, and one
## spare overcharge pip faults eventually (once per heating episode, D219). M1 corvette:
## 12 reactor pips, 20 MW, two weapon pips of 2 nominal.


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1)
	return w


func _row(w: SimWorld, id: StringName) -> int:
	return w.damage.find_subsystem(0, id)


func _pips_total(w: SimWorld) -> int:
	var total: int = 0
	for p: int in SimFixture.sub_values(w, 0, "pips"):
		total += p
	return total


## Energy the weapons store gains in 60 ticks from empty (J).
func _recharge(w: SimWorld) -> float:
	w.power.weapon_energy[0] = 0.0
	for i: int in 60:
		w.step()
	return w.power.weapon_energy[0]


func _set_pips(w: SimWorld, kind: int, pips: int) -> bool:
	var c: SetPipsCommand = SetPipsCommand.new()
	c.ship_id = 0
	c.subsystem_kind = kind
	c.pips = pips
	w.submit(c)
	var logged: int = w.accepted_commands().size()
	w.step()
	return w.accepted_commands().size() > logged


# FT: FT-SIM-026
# Reactor health 0 gives no charge and no pips; a hack at 0.5 halves the charge and the
# usable pips (12 -> 6); the pips come back as a limit only (repair does not refill them).
func test_reactor_health_and_hack_scale_output_and_pip_cap() -> void:
	var full: float = _recharge(_world())
	assert_float(full).is_equal_approx(20e6 * 2.0 / 12.0, 1e3)
	var hacked: SimWorld = _world()
	hacked.damage.hack_scale[_row(hacked, &"reactor")] = 0.5
	var half: float = _recharge(hacked)
	# Output halves and the 10 pips scale to 6 usable: one pip on each of five subsystems,
	# so the weapons' pips halve too (a quarter of the charge).
	assert_float(half).is_equal_approx(0.25 * full, 1e4)
	assert_int(_pips_total(hacked)).is_less_equal(6)
	assert_bool(_set_pips(hacked, SubsystemDef.Kind.ENGINES, 4)).is_false()
	var dead: SimWorld = _world()
	dead.damage.health[_row(dead, &"reactor")] = 0.0
	assert_float(_recharge(dead)).is_equal(0.0)
	assert_int(_pips_total(dead)).is_equal(0)
	dead.damage.health[_row(dead, &"reactor")] = 2e7
	dead.step()
	assert_int(_pips_total(dead)).is_equal(0)
	assert_bool(_set_pips(dead, SubsystemDef.Kind.ENGINES, 2)).is_true()


# FT: FT-SIM-012, FT-SIM-021
# A destroyed weapons subsystem still recharges the store at half rate (A1 floor).
func test_weapons_health_scales_the_charge_down_to_a_floor() -> void:
	var full: float = _recharge(_world())
	var w: SimWorld = _world()
	w.damage.health[_row(w, &"weapons")] = 0.0
	assert_float(_recharge(w)).is_equal_approx(0.5 * full, 1e3)


# FT: FT-SIM-026
# One overcharge pip (3 on shields) heats toward 5 / 0.05 = 100 K, above the 95 K
# threshold: exactly one fault in ten minutes, not none and not a stream (D219).
func test_one_spare_pip_faults_once_per_episode() -> void:
	var w: SimWorld = _world()
	assert_bool(_set_pips(w, SubsystemDef.Kind.SHIELDS, 3)).is_true()
	var faults: int = 0
	var first: int = -1
	for i: int in 600 * SimWorld.HZ:
		w.step()
		for e: SimEvent in w.drain_events():
			if e.kind == &"fault":
				faults += 1
				first = i if first < 0 else first
	assert_int(faults).is_equal(1)
	# Heat reaches 95 K at t = ln(100 / 5) / 0.05 = 59.9 s.
	assert_float(first / float(SimWorld.HZ)).is_equal_approx(59.9, 0.5)


# FT: FT-SIM-026
# Every overcharging subsystem's one-pip equilibrium heat is above its fault threshold,
# so no data file brings back a free spare pip (R16-1).
func test_one_pip_equilibrium_is_above_every_threshold() -> void:
	for def: ShipDef in [TestDefs.corvette(), TestDefs.raider()]:
		for sd: SubsystemDef in def.subsystems:
			if sd.kind != SubsystemDef.Kind.REACTOR and sd.heat_dissipation > 0.0:
				var equilibrium: float = sd.heat_per_overcharge_pip / sd.heat_dissipation
				assert_float(equilibrium).override_failure_message(String(sd.id)).is_greater(
					sd.fault_heat_threshold
				)
