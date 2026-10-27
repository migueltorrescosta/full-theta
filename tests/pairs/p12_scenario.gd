class_name P12Scenario
extends RefCounted
## P12 Engineering + Comms pair scenario (spec §7.4, D57, D68, FT-PAIR-010, FT-PAIR-015):
## the corvette, docked at SITE with credits, a faulted engine and a damaged tractor.
## Engineering and Comms talk only by voice (no data link at any difficulty), so the scripts
## model the voice: what Engineering says is what the co-op Comms script knows.
## What Comms buys lands in COND: parts in Engineering's spares, a dock repair clears the
## fault. An offer (a CONTRACT card) needs power 2 on the tractor (StoryRules.needs_met),
## which Comms can't see (it has the hull band only) and may accept.
## - Co-op: Engineering says the tractor is damaged; Comms declines the offer.
## - Solo: Comms accepts on its fixed view of condition, and the offer fails at its
##   deadline (rep.complete_mission.fail).
## The pair test is exempt from "co-op beats solo" (FT-PAIR-015); the comparison here shows
## what the voice saves.

const SEED: int = 12
const PLAYER: int = 0
const BLUE: int = StoryFixture.BLUE
const RED: int = StoryFixture.RED
const SITE: int = StoryFixture.SITE
const CREDITS: int = 1000
const TRACTOR_LEFT: float = 0.3
const TRACTOR_PIPS: int = 2
const DEADLINE_S: float = 10.0
const TICK_LIMIT: int = 20 * SimWorld.HZ


## The corvette with a tractor (a copy of its thrusters under another id, so the damage
## model has a subsystem of that name; the pips the tractor needs are the subsystem's
## effectiveness times the pips one subsystem holds).
static func tractor_ship() -> ShipDef:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var tractor: SubsystemDef = TestDefs.corvette().subsystems[1].duplicate()
	tractor.id = &"tractor"
	var subs: Array[SubsystemDef] = []
	subs.assign(def.subsystems.duplicate())
	subs.append(tractor)
	def.subsystems = subs
	return def


static func harness() -> PairHarness:
	return PairHarness.new(build, environment, done, measure, TICK_LIMIT)


## Docked, 1000 credits, the engines faulted and the tractor at TRACTOR_LEFT of its health.
static func build() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.spawn_ship(tractor_ship(), BLUE)
	Economy.add_credits(w, PLAYER, CREDITS)
	StoryFixture.dock(w, PLAYER)
	var engines: int = w.damage.find_subsystem(PLAYER, &"engines")
	w.damage.health[engines] *= 0.4
	w.damage.fault_cause[engines] = &"coolant_leak"
	set_tractor(w, TRACTOR_LEFT)
	return w


## Leaves the tractor with `left` of its health.
static func set_tractor(w: SimWorld, left: float) -> void:
	var row: int = w.damage.find_subsystem(PLAYER, &"tractor")
	w.damage.health[row] = (
		left * w.defs[PLAYER].subsystems[row - w.damage.hull_row(PLAYER) - 1].health_max
	)


## The server posts the market's offer (card 0) and the tractor job (card 1) at tick 0, and
## settles the job at the deadline: won when the tractor can supply its power.
static func environment(w: SimWorld) -> void:
	if w.tick == 0:
		PairHarness.send(w, StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE))
		var job: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT)
		job.title_key = "comms.card.contract"
		job.reward_credits = 200
		job.rep_interaction = &"rep.complete_mission"
		job.rep_faction = RED
		job.needs_subsystem = &"tractor"
		job.needs_pips = TRACTOR_PIPS
		PairHarness.send(w, job)
	elif w.tick == roundi(DEADLINE_S * SimWorld.HZ) and w.story.size() > 1:
		if w.story.state[1] == StoryTable.State.ACCEPTED:
			var r: CardResultCommand = CardResultCommand.new()
			r.card = 1
			r.success = StoryRules.needs_met(w, PLAYER, 1)
			PairHarness.send(w, r)


static func done(w: SimWorld) -> bool:
	return w.story.size() > 1 and not Story.is_live(w, 1)


static func measure(w: SimWorld) -> Dictionary:
	return {
		"rep_lost": maxf(0.0, -w.reputation.value_of(BLUE, RED)),
		"credits": float(Economy.credits(w, PLAYER)),
	}


static func solo(w: SimWorld) -> void:
	if w.tick == 2:
		var a: AcceptCardCommand = AcceptCardCommand.new()
		a.card = 1
		PairHarness.send(w, a)


## Engineering has said the tractor is damaged: Comms declines the job.
static func coop(w: SimWorld) -> void:
	if w.tick == 2:
		var d: DeclineCardCommand = DeclineCardCommand.new()
		d.card = 1
		PairHarness.send(w, d)


## Comms buys `qty` of an item at the docked market (card 0).
static func buy(w: SimWorld, item: StringName, qty: int = 1) -> bool:
	var c: TradeCommand = TradeCommand.new()
	c.card = 0
	c.item = item
	c.qty = qty
	return StoryFixture.run(w, PLAYER, c)
