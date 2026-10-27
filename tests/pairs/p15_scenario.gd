class_name P15Scenario
extends RefCounted
## P15 Relay + Comms pair scenario (spec §7.4, FT-PAIR-015): a mission whose place is vague.
## The card (a MISSION, target a derelict) names three spots where the derelict may be; it is
## at the third, TRUTH, beyond the corvette's sensors from the other two. The corvette is at
## the origin; the objective is to come within CAPTURE of the derelict.
## - Co-op: Comms reads the mission and Relay resolves its place: it marks the mission
##   (MarkMissionCommand; Comms' card gets the mission icon under mission_icon) and gives
##   Helm the exact point, which Helm flies to.
## - Solo: Helm searches the three spots in the order the card lists them, and turns on the
##   derelict as soon as its sensors detect it (FT-PAIR-004).
## Metric: seconds to the objective.

const SEED: int = 15
const PLAYER: int = 0
const DERELICT: int = 1
const BLUE: int = StoryFixture.BLUE
const RED: int = StoryFixture.RED
const TRUTH: Vector3 = Vector3(-25000.0, 0.0, -25000.0)
const SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, -25000.0), Vector3(25000.0, 0.0, -25000.0), TRUTH]
const CAPTURE: float = 100.0
const MARK_TICK: int = 5
const TICK_LIMIT: int = 1500 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.spawn_ship(TestDefs.corvette(), BLUE)
	w.spawn_ship(TestDefs.raider(), RED, TRUTH)
	return w


## The server posts the mission at tick 0.
static func environment(w: SimWorld) -> void:
	if w.tick == 0:
		var c: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
		c.title_key = "comms.card.mission"
		c.target = DERELICT
		PairHarness.send(w, c)


static func done(w: SimWorld) -> bool:
	return w.kin.relative_to_point(PLAYER, TRUTH.x, TRUTH.y, TRUTH.z).length() < CAPTURE


static func measure(w: SimWorld) -> Dictionary:
	return {"seconds": w.tick * SimWorld.DT}


## Relay marks the mission once it exists, then Helm flies to the mark.
static func coop(w: SimWorld) -> void:
	if w.tick == MARK_TICK:
		var m: MarkMissionCommand = MarkMissionCommand.new()
		m.card = 0
		PairHarness.send(w, m)
	if StoryRules.is_marked(w, 0):
		if w.tick == MARK_TICK + 1:
			PairHarness.send(w, PairHarness.helm_input(0.0))  # holds Face on the point
		P4Scenario.helm(w, [TRUTH] as Array[Vector3])


## Helm searches the spots in order, or flies at the derelict once it sees it.
static func solo(w: SimWorld) -> void:
	var seen: bool = KnowledgeSystem.is_detected(w, BLUE, DERELICT)
	P4Scenario.helm(w, [TRUTH] as Array[Vector3] if seen else SPOTS)


## The corvette and, 30 km ahead (beyond its 20 km sensors), a raider that can be hailed.
static func discovery_world() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.spawn_ship(TestDefs.corvette(), BLUE)
	w.spawn_ship(TestDefs.raider(), RED, Vector3(0.0, 0.0, -30000.0))
	return w


## Relay launches a probe 24 km ahead at tick 0; its 8 km bubble covers the raider once it
## has deployed.
static func probe(w: SimWorld) -> void:
	if w.tick == 0:
		var c: LaunchProbeCommand = LaunchProbeCommand.new()
		c.ship_id = PLAYER
		c.z = -24000.0
		w.submit(c)
