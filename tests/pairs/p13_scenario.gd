class_name P13Scenario
extends RefCounted
## P13 Science + Relay pair scenario (spec §7.4, FT-PAIR-015, D56): the M1 corvette holds
## station (Helm's course is P3, not this pair) while a hostile raider closes on it from
## 30 km at 100 m/s, bow-on. The corvette's sensors reach 20 km, so the raider is not a
## contact for 100 s. Science scans it and hacks its weapons (the hack-window opening
## ends the run).
## - Solo: Science waits until its own sensors detect the raider (ScienceHand).
## - Co-op: Relay launches a probe at tick 0 to the point 24 km ahead on the raider's
##   bearing (the bearing is what the mission brief gives), its 8 km bubble covers the
##   raider from the moment it deploys; Science works through the probe: scan noise and
##   the hack's trace are lower in the bubble (FT-SCI-005, FT-RLY-004).
## Metrics: time to the open hack window (s), peak of the hack's trace bar (0..1),
## range of the contact when the scan opened (m, higher is better: reached beyond the
## sensors' 20 km), and whether that scan ran on a probe (0 or 1).

const SEED: int = 53
const PLAYER: int = 0
const RAIDER: int = 1
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -30000.0)
## The raider's cruise speed (m/s), bow on the corvette: its throttle is held until the
## setpoint reaches it (the speed follows with a lag), then released, which keeps it.
const RAIDER_SPEED: float = 100.0
## Where Relay sends the probe (m, site frame).
const PROBE_AT: Vector3 = Vector3(0.0, 0.0, -24000.0)
const TICK_LIMIT: int = 200 * SimWorld.HZ
const PLAYER_SEED: int = 5
const HACKED: StringName = &"weapons"


## What the environment saw during a run (the world stores a trace bar only while its
## hack is open): reset by every build.
class Seen:
	extends RefCounted
	var trace_peak: float = 0.0
	var scan_range: float = 0.0
	var scan_on_probe: float = 0.0


static func harness() -> PairHarness:
	var seen: Seen = Seen.new()
	var build_fresh: Callable = func() -> SimWorld:
		seen.trace_peak = 0.0
		seen.scan_range = 0.0
		seen.scan_on_probe = 0.0
		return build()
	var observe: Callable = func(w: SimWorld) -> void: _observe(w, seen)
	var measured: Callable = func(w: SimWorld) -> Dictionary: return measure(w, seen)
	return PairHarness.new(build_fresh, observe, done, measured, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p13")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	w.spawn_ship(TestDefs.raider(), 2, 0, RAIDER_AT, Quaternion(Vector3.UP, PI))
	return w


static func done(w: SimWorld) -> bool:
	return w.hacks.size() > 0


static func measure(w: SimWorld, seen: Seen) -> Dictionary:
	return {
		"time": w.tick * SimWorld.DT,
		"trace_peak": seen.trace_peak,
		"scan_range": seen.scan_range,
		"scan_on_probe": seen.scan_on_probe,
	}


static func _observe(w: SimWorld, seen: Seen) -> void:
	var want: float = 1.0 if w.helm.throttle_setpoint[RAIDER] < RAIDER_SPEED else 0.0
	if w.helm.input_translation[RAIDER].z != want:
		var drive: HelmInputCommand = HelmInputCommand.new()
		drive.ship_id = RAIDER
		drive.throttle = want
		w.submit(drive)
	var t: ScienceTable = w.science
	if t.kind[PLAYER] == ScienceTable.Session.SCAN and seen.scan_range == 0.0:
		seen.scan_range = w.kin.relative(PLAYER, RAIDER).length()
		seen.scan_on_probe = float(t.probe[PLAYER])
	if t.kind[PLAYER] == ScienceTable.Session.HACK:
		seen.trace_peak = maxf(seen.trace_peak, t.trace[PLAYER])


static func solo_crew() -> Callable:
	var hand: ScienceHand = _hand()
	return func(w: SimWorld) -> void: hand.act(w)


static func coop_crew() -> Callable:
	var hand: ScienceHand = _hand()
	return func(w: SimWorld) -> void:
		relay(w)
		hand.act(w)


## Relay (co-op): launches the probe at the start.
static func relay(w: SimWorld) -> void:
	if w.tick == 0:
		var c: LaunchProbeCommand = LaunchProbeCommand.new()
		c.ship_id = PLAYER
		c.x = PROBE_AT.x
		c.y = PROBE_AT.y
		c.z = PROBE_AT.z
		w.submit(c)


static func _hand() -> ScienceHand:
	var hand: ScienceHand = ScienceHand.new(PLAYER, RAIDER, PLAYER_SEED)
	hand.hack_subsystem = HACKED
	return hand
