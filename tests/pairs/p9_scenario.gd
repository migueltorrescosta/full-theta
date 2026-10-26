class_name P9Scenario
extends RefCounted
## P9 Weapons + Comms pair scenario (spec §7.4, FT-PAIR-015): the M1 corvette at the origin,
## a raider 2 km ahead, at rest, with its engines already shot up. Comms has accepted a
## contract on the raider, "disable, do not destroy" (DISABLE in KNOW, FT-MIS-042), worth
## REWARD credits and the contract reputation draw; at DEADLINE_S the contract is settled
## as won if the raider is alive and surrendering, else as lost (the raider's destruction
## already failed it, StoryRules.on_destroyed).
## - Comms (both variants): hails the raider and demands its surrender until it yields
##   (conv.surrender_demand; the chance rises with the engine damage).
## - Weapons co-op: sees the contact's intent and the contract flag (the reticle chip under
##   contract_flags, or Comms' call) and stops firing once it surrenders.
## - Weapons solo: fires at anything, with no word from Comms.
## Metrics: reputation lost, reward earned, and whether the raider was destroyed.

const SEED: int = 109
const PLAYER: int = 0
const RAIDER: int = 1
const BLUE: int = 1
const RED: int = 2
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -2000.0)
const REWARD: int = 500
const SHIELD_J: float = 1.0e5
const HULL_J: float = 6.0e6
const ACCEPT_TICK: int = 2
const HAIL_TICK: int = 3
const FIRE_TICK: int = 5
const DEADLINE_S: float = 30.0
## The raider's engines have this share of their health left.
const ENGINES_LEFT: float = 0.2
const TICK_LIMIT: int = 60 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.hail_conversations = {&"m1_raider": &"conv.surrender_demand"}
	w.set_relation(BLUE, RED, SimWorld.Relation.HOSTILE)
	w.spawn_ship(TestDefs.corvette(), BLUE)
	w.spawn_ship(raider_def(), RED, RAIDER_AT)
	damage_engines(w, ENGINES_LEFT)
	return w


## A raider with a thin hull and little shield: three or four hits destroy it.
static func raider_def() -> ShipDef:
	var def: ShipDef = Gunnery.raider_with_shields(SHIELD_J)
	def.hull_max = HULL_J
	return def


## Leaves the raider's engines with `left` of their health.
static func damage_engines(w: SimWorld, left: float) -> void:
	var row: int = w.damage.find_subsystem(RAIDER, &"engines")
	w.damage.health[row] *= left


## The server posts the contract at tick 0 and settles it at the deadline.
static func environment(w: SimWorld) -> void:
	if w.tick == 0:
		var c: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT)
		c.title_key = "comms.card.contract"
		c.target = RAIDER
		c.target_flag = KnowledgeTable.Flag.DISABLE
		c.reward_credits = REWARD
		c.rep_interaction = &"rep.complete_mission"
		PairHarness.send(w, c)
	elif w.tick == roundi(DEADLINE_S * SimWorld.HZ) and Story.is_live(w, 0):
		var r: CardResultCommand = CardResultCommand.new()
		r.card = 0
		r.success = surrendering(w) and w.kin.is_alive(RAIDER)
		PairHarness.send(w, r)


static func done(w: SimWorld) -> bool:
	return w.story.size() > 0 and not Story.is_live(w, 0)


static func measure(w: SimWorld) -> Dictionary:
	return {
		"rep_lost": maxf(0.0, -w.reputation.value_of(BLUE, RED)),
		"reward": float(Economy.credits(w, PLAYER)),
		"destroyed": float(not w.kin.is_alive(RAIDER)),
	}


static func surrendering(w: SimWorld) -> bool:
	var row: int = w.knowledge.row_for(BLUE, RAIDER)
	return row >= 0 and w.knowledge.intent[row] == KnowledgeTable.Intent.SURRENDERING


## Comms: accepts the contract, hails the raider and asks again until it surrenders.
static func comms(w: SimWorld) -> void:
	if w.tick == ACCEPT_TICK:
		var a: AcceptCardCommand = AcceptCardCommand.new()
		a.card = 0
		PairHarness.send(w, a)
	elif w.tick == HAIL_TICK:
		var h: HailCommand = HailCommand.new()
		h.target = RAIDER
		PairHarness.send(w, h)
	elif w.tick > HAIL_TICK and w.story.size() > 1 and not surrendering(w):
		if Story.is_live(w, 1) and w.story.node[1] != StoryTable.NO_TEXT:
			var r: ReplyCommand = ReplyCommand.new()
			r.card = 1
			r.option = &"o1"
			PairHarness.send(w, r)


## Weapons: fires every mount at the raider. `holds` is true for the co-op gunner, who stops
## once the raider surrenders.
static func gunner(w: SimWorld, holds: bool) -> void:
	if w.tick < FIRE_TICK or (holds and surrendering(w)):
		return
	Gunnery.gun(w, PLAYER, Gunnery.site_point(w, RAIDER, Vector3.ZERO))


static func coop(w: SimWorld) -> void:
	comms(w)
	gunner(w, true)


static func solo(w: SimWorld) -> void:
	comms(w)
	gunner(w, false)
