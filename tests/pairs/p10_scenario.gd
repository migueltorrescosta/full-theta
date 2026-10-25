class_name P10Scenario
extends RefCounted
## P10 Engineering + Science pair scenario (spec §7.4, FT-PAIR-015, FT-SIM-025): the M1
## corvette's engines take a fault of unknown cause (it lists three possible causes, the
## true one is not the first, so a blind pick is wrong). One repair crew works on it.
## - Engineering (both variants): sends the crew to the engines at once.
## - Science (co-op only): runs the own-ship scan; once it names the cause
##   (DamageSystem.known_fault_cause) Engineering picks it, so the repair runs at full
##   rate (FT-ENG-006).
## - Solo: nobody names the cause, Engineering never picks one and the repair runs at the
##   brute-force rate (FT-PAIR-004).
## Metric: time (s) until the fault is cleared (both variants use one part).

const SEED: int = 110
const PLAYER: int = 0
const CAUSES: Array[StringName] = [&"coolant_leak", &"short", &"software"]
const CAUSE: StringName = &"software"
## The fault's energy (J): 12 s of one crew at full rate (repair_rate 2e5 J/s).
const FAULT_J: float = 2.4e6
const SUBSYSTEM: StringName = &"engines"
const TICK_LIMIT: int = 120 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, no_environment, done, measure, TICK_LIMIT)


## The faulty corvette, built as a copy of the M1 definition with the cause list
## (definitions are read-only, FT-ARC-020). The fault exists from tick 0.
static func build() -> SimWorld:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == SUBSYSTEM:
			copy.fault_causes = CAUSES
		subs.append(copy)
	def.subsystems = subs
	var w: SimWorld = SimWorld.new(SEED, "p10")
	w.science_def = ScienceFixture.science()
	w.spawn_ship(def, 1, 0)
	DamageSystem.inflict_fault(w, PLAYER, SUBSYSTEM, CAUSE, FAULT_J)
	return w


static func no_environment(_w: SimWorld) -> void:
	pass


static func done(w: SimWorld) -> bool:
	var row: int = w.damage.find_subsystem(PLAYER, SUBSYSTEM)
	return w.damage.fault_cause[row] == &""


static func measure(w: SimWorld) -> Dictionary:
	return {"time": w.tick * SimWorld.DT}


static func solo(w: SimWorld) -> void:
	engineering(w)


static func coop(w: SimWorld) -> void:
	science(w)
	engineering(w)


## Engineering: crew 0 to the engines on the first tick; in co-op, picks the named cause.
static func engineering(w: SimWorld) -> void:
	if w.tick == 0:
		var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
		dispatch.crew = 0
		dispatch.subsystem_id = SUBSYSTEM
		_submit(w, dispatch)


static func science(w: SimWorld) -> void:
	if w.tick == 0:
		_submit(w, ScienceSelfScanCommand.new())
	var named: StringName = DamageSystem.known_fault_cause(w, PLAYER, SUBSYSTEM)
	var row: int = w.damage.find_subsystem(PLAYER, SUBSYSTEM)
	if named != &"" and w.damage.fault_pick[row] != named:
		var pick: PickFaultCauseCommand = PickFaultCauseCommand.new()
		pick.subsystem_id = SUBSYSTEM
		pick.cause = named
		_submit(w, pick)


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = PLAYER
	w.submit(c)
