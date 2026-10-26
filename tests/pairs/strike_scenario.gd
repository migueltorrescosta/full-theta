class_name StrikeScenario
extends RefCounted
## The long-range engagement behind P8 (Weapons + Relay) and the Over-horizon strike
## play (R -> S -> W; spec §7.4, FT-PAIR-015, FT-PAIR-022). A short-sighted corvette
## (sensors 5 km, one missile mount, missiles reach 8 km) faces a hostile raider 10 km
## dead ahead, bow-on, closing at 100 m/s without firing. The raider's weapons are its
## weak point (revealed to the shooter's faction by a scan at confidence 0.6 or more) and
## it carries almost no shields, so the metric is clean: seconds until its weapons
## subsystem is destroyed ("disabled"), and until the first missile hits it.
##
## The crew is assembled from three optional parts, each a station's work:
## - Relay (use_probe): launches a probe at tick 0 to the point 7 km ahead (the bearing
##   is what the brief gives); its 8 km bubble covers the raider from deployment, so the
##   raider is tracked (GuidanceSystem.is_tracked) and detected from 14 s on, instead of
##   from 5 km (50 s, when it is in the corvette's own sensors);
## - Science (use_scan): ScienceHand scans the raider as soon as it is a contact (through
##   the probe when there is one) and so reveals the weak point (FT-SIM-023);
## - Weapons (always): fires one guided missile per cooldown at the raider while it is
##   tracked, within FIRE_RANGE and the track's quality bar (GuidanceSystem.track_quality,
##   D214) is at FIRE_QUALITY or more: a missile on a poor track turns slowly and is
##   wasted. With use_track off Weapons ignores what the probe tracks and waits for its own
##   sensors (the Relay -> Weapons link removed).

const SEED: int = 61
const PLAYER: int = 0
const RAIDER: int = 1
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -10000.0)
const RAIDER_SPEED: float = 100.0
const PROBE_AT: Vector3 = Vector3(0.0, 0.0, -7000.0)
## The corvette's own sensor range (m).
const SENSOR_RANGE: float = 5000.0
## Weapons fires while the raider is closer than this (m); the missile's range is 8 km.
const FIRE_RANGE: float = 7500.0
## Weapons holds fire below this track quality (dimensionless, 0..1).
const FIRE_QUALITY: float = 0.3
## The share of a hit past the shields that the raider's revealed weak point takes.
const WEAK_POINT_SHARE: float = 0.9
const TICK_LIMIT: int = 200 * SimWorld.HZ
const PLAYER_SEED: int = 7
const WEAPONS: StringName = &"weapons"
const MISSILE: String = "res://content/weapons/m2_missile.tres"


## Hold the returned crew's parts as variants: a station that is off sends nothing.
static func harness() -> PairHarness:
	return PairHarness.new(build, drive_raider, done, measure, TICK_LIMIT)


static func shooter_def() -> ShipDef:
	var ship: ShipDef = TestDefs.corvette().duplicate()
	ship.sensor_range = SENSOR_RANGE
	ship.identify_range = minf(ship.identify_range, SENSOR_RANGE)
	var mount: MountDef = ship.mounts[0].duplicate()
	mount.weapon = load(MISSILE) as WeaponDef
	var mounts: Array[MountDef] = [mount]
	ship.mounts = mounts
	return ship


## The raider: its weapons are a weak point, its shields a token.
static func raider_def() -> ShipDef:
	var ship: ShipDef = TestDefs.raider().duplicate()
	var subs: Array[SubsystemDef] = []
	subs.assign(ship.subsystems.duplicate())
	for i: int in subs.size():
		if subs[i].id == WEAPONS:
			var weak: SubsystemDef = subs[i].duplicate()
			weak.weak_point = true
			weak.weak_point_share = WEAK_POINT_SHARE
			subs[i] = weak
	ship.subsystems = subs
	var shields: ShieldDef = ship.shields.duplicate()
	shields.max_strength = 1000.0
	shields.regen_rate = 0.0
	ship.shields = shields
	return ship


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "strike")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(shooter_def(), 1)
	w.spawn_ship(raider_def(), 2, RAIDER_AT, Quaternion(Vector3.UP, PI))
	return w


## The raider's helm (both variants): throttle held until the speed setpoint is
## RAIDER_SPEED, then released, which keeps the setpoint.
static func drive_raider(w: SimWorld) -> void:
	var want: float = 1.0 if w.helm.throttle_setpoint[RAIDER] < RAIDER_SPEED else 0.0
	if w.helm.input_translation[RAIDER].z != want:
		var drive: HelmInputCommand = HelmInputCommand.new()
		drive.ship_id = RAIDER
		drive.throttle = want
		w.submit(drive)


static func done(w: SimWorld) -> bool:
	return w.damage.health[_weapons_row(w)] <= 0.0


static func measure(w: SimWorld) -> Dictionary:
	var hits: Array[SimEvent] = SimFixture.of_kind(w.events, &"hit").filter(
		func(e: SimEvent) -> bool: return e.ship_id == RAIDER
	)
	var first: float = hits[0].tick * SimWorld.DT if not hits.is_empty() else NAN
	var weak: int = SimFixture.of_kind(w.events, &"weak_point_hit").size()
	return {
		"time": w.tick * SimWorld.DT,
		"first_hit_s": first,
		"hits": float(hits.size()),
		"weak_point_hits": float(weak),
	}


## A crew: Weapons plus the parts switched on. A fresh one per run. `shots` collects the
## track quality of each missile fired.
static func crew(
	use_probe: bool, use_scan: bool, use_track: bool, shots: Array[float] = []
) -> Callable:
	var hand: ScienceHand = ScienceHand.new(PLAYER, RAIDER, PLAYER_SEED)
	return func(w: SimWorld) -> void:
		if use_probe:
			relay(w)
		if use_scan:
			hand.act(w)
		weapons(w, use_track, shots)


## Relay: launches the probe at the start.
static func relay(w: SimWorld) -> void:
	if w.tick == 0:
		var c: LaunchProbeCommand = LaunchProbeCommand.new()
		c.ship_id = PLAYER
		c.x = PROBE_AT.x
		c.y = PROBE_AT.y
		c.z = PROBE_AT.z
		w.submit(c)


## Weapons: one guided missile per cooldown at the raider while it is in range and
## tracked, by the probe or not (use_track), else by the own sensors alone.
static func weapons(w: SimWorld, use_track: bool, shots: Array[float] = []) -> void:
	var dist: float = w.kin.relative(PLAYER, RAIDER).length()
	if w.mounts.cooldown[0] > 0.0 or w.mounts.ammo[0] <= 0 or dist > FIRE_RANGE:
		return
	var tracked: bool = GuidanceSystem.is_tracked(w, w.faction_of(PLAYER), RAIDER)
	if not use_track:
		tracked = dist <= w.defs[PLAYER].sensor_range
	var quality: float = GuidanceSystem.track_quality(w, w.faction_of(PLAYER), RAIDER)
	if tracked and quality >= FIRE_QUALITY:
		var c: FireGuidedCommand = FireGuidedCommand.new()
		c.ship_id = PLAYER
		c.target = RAIDER
		w.submit(c)
		shots.append(quality)


static func _weapons_row(w: SimWorld) -> int:
	return w.damage.find_subsystem(RAIDER, WEAPONS)
