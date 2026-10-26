class_name P5Scenario
extends RefCounted
## P5 Helm + Comms pair scenario (spec §7.4, FT-PAIR-015): the M1 corvette, at rest at the
## origin with its bow on -Z, must dock at a yard 5 km dead ahead. The yard asks for
## clearance (a CONTRACT card tied to its site): the lane opens LANE_OPEN_S after Comms
## accepts it and stays open LANE_S; docking outside the window loses reputation with the
## yard's faction (StoryRules.on_dock, rep.uncleared_approach).
## - Comms (both variants): accepts the clearance at once. Comms alone can do that and
##   negotiate (FT-PAIR-004).
## - Helm co-op: sees the lane (StoryRules.lane_window, what the Helm lane draws under the
##   lanes toggle) and flies at the speed that brings it to the yard in the middle of the
##   window.
## - Helm solo: has no lane and rushes at CRUISE_SOLO, arriving before the window opens.
## The dock itself is the environment's: StoryFixture.dock stops the ship and applies the
## real DockCommand (HelmTable.docked_site) at the yard, a dockable site of the SiteTable.
## Metrics: reputation lost with the yard's faction, and seconds to dock.

const SEED: int = 105
const PLAYER: int = 0
const BLUE: int = 1
const YARD_FACTION: int = 3
const YARD_AT: Vector3 = Vector3(0.0, 0.0, -5000.0)
const DOCK_R: float = 200.0
const LANE_OPEN_S: float = 70.0
const LANE_S: float = 40.0
const ACCEPT_TICK: int = 2
const CRUISE_SOLO: float = 100.0
const ON_POINT: float = PI / 36.0
const TICK_LIMIT: int = 240 * SimWorld.HZ

static var _yard: int = -1


static func harness() -> PairHarness:
	return PairHarness.new(build, environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.spawn_ship(TestDefs.corvette(), BLUE)
	w.sites.register(&"yard", YARD_AT, 500.0, &"station")
	_yard = w.sites.open(w, &"yard")
	return w


## The server posts the clearance at tick 0; the environment docks the ship at the yard.
static func environment(w: SimWorld) -> void:
	if w.tick == 0:
		var c: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"", _yard)
		c.title_key = "comms.card.clearance"
		c.rep_faction = YARD_FACTION
		c.lane_open_s = LANE_OPEN_S
		c.lane_s = LANE_S
		PairHarness.send(w, c)
	if (
		Story.docked_site(w, PLAYER) < 0
		and w.kin.relative_to_point(PLAYER, YARD_AT.x, YARD_AT.y, YARD_AT.z).length() < DOCK_R
	):
		StoryFixture.dock(w, PLAYER, _yard)


static func done(w: SimWorld) -> bool:
	return w.story.size() > 0 and not Story.is_live(w, 0)


static func measure(w: SimWorld) -> Dictionary:
	return {
		"rep_lost": maxf(0.0, -w.reputation.value_of(BLUE, YARD_FACTION)),
		"seconds": w.tick * SimWorld.DT,
		"cleared": float(w.story.state[0] == StoryTable.State.DONE),
	}


## Comms: accepts the clearance.
static func comms(w: SimWorld) -> void:
	if w.tick == ACCEPT_TICK:
		var c: AcceptCardCommand = AcceptCardCommand.new()
		c.card = 0
		PairHarness.send(w, c)


static func solo(w: SimWorld) -> void:
	comms(w)
	helm(w, CRUISE_SOLO)


## Helm reads the lane and fixes, once, the speed that brings it to the yard in the middle
## of the window. A fresh script per run.
static func coop_crew() -> Callable:
	var speed: Array[float] = [0.0]
	return func(w: SimWorld) -> void:
		comms(w)
		var window: Array[int] = StoryRules.lane_window(w, 0)
		if window.is_empty():
			return
		if speed[0] == 0.0:
			var middle_s: float = (window[0] + window[1]) / 2.0 * SimWorld.DT
			var to_yard: float = (
				w.kin.relative_to_point(PLAYER, YARD_AT.x, YARD_AT.y, YARD_AT.z).length()
			)
			speed[0] = (to_yard - DOCK_R) / (middle_s - w.tick * SimWorld.DT)
		helm(w, speed[0])


## Helm flying at the yard at `speed` (m/s): selects its point, holds Face, ramps the speed
## setpoint up to `speed` once the bow is on it, then leaves the throttle alone.
static func helm(w: SimWorld, speed: float) -> void:
	if w.helm.target_kind[PLAYER] != HelmTable.Target.POINT:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.point = true
		select.x = YARD_AT.x
		select.y = YARD_AT.y
		select.z = YARD_AT.z
		PairHarness.send(w, select)
	var to_yard: Vector3 = w.kin.relative_to_point(PLAYER, YARD_AT.x, YARD_AT.y, YARD_AT.z)
	var on_point: bool = w.kin.forward(PLAYER).angle_to(to_yard) < ON_POINT
	var throttle: float = 1.0 if w.helm.throttle_setpoint[PLAYER] < speed and on_point else 0.0
	if w.tick == 0 or throttle != w.helm.input_translation[PLAYER].z:
		PairHarness.send(w, PairHarness.helm_input(throttle))
