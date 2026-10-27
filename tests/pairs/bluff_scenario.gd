class_name BluffScenario
extends RefCounted
## The Bluff call play (spec §7.4, FT-PAIR-022, D201): C->S->C->W, pairs P14 and P9. A
## trader (RED's raider, a thin hull) 3 km ahead claims to be harmless, and a standing
## bounty on contraband runners (a CONTRACT card on it, REWARD credits and the contract
## reputation draw) pays only if it turns out to be one.
## 1. Comms hails the trader and hears its claim (conv.trader_bluff, node n0).
## 2. Science scans it; the scan learns the fact "cargo" (StoryRules.learn_scan_facts).
## 3. Comms calls the bluff (option o3, which needs that fact): reputation draw
##    rep.call_bluff, and the faction's intent for the trader becomes BLUFFING.
## 4. Weapons acts on the new intent and fires at the trader; it holds fire while the
##    intent is not BLUFFING. The environment settles the bounty as won when the trader
##    is destroyed while BLUFFING.
## A chain with a link removed leaves that station's step out (crew()). Metrics: the
## reputation with RED and the credits earned.

enum Link { HEAR_CLAIM, SCAN, CALL_BLUFF, ACT }

const SEED: int = 11
const PLAYER: int = 0
const TRADER: int = 1
const BLUE: int = 1
const RED: int = 2
const TRADER_AT: Vector3 = Vector3(0.0, 0.0, -3000.0)
const REWARD: int = 400
const SHIELD_J: float = 1.0e5
const HULL_J: float = 6.0e6
const HAIL_TICK: int = 3
const SCAN_AT: int = 2
## Weapons fires from this tick on, once the intent is BLUFFING.
const TICK_LIMIT: int = 120 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = StoryFixture.world(SEED)
	w.science_def = ScienceFixture.science()
	w.set_relation(BLUE, RED, SimWorld.Relation.HOSTILE)
	w.spawn_ship(Gunnery.gunship(1), BLUE)
	var def: ShipDef = Gunnery.raider_with_shields(SHIELD_J)
	def.hull_max = HULL_J
	w.spawn_ship(def, RED, TRADER_AT)
	return w


## The server posts the bounty at tick 0; it is settled as won when the trader dies
## bluffing.
static func environment(w: SimWorld) -> void:
	if w.tick == 0:
		var c: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT)
		c.title_key = "comms.card.contract"
		c.target = TRADER
		c.reward_credits = REWARD
		c.rep_interaction = &"rep.complete_mission"
		PairHarness.send(w, c)
	elif w.story.size() > 0 and Story.is_live(w, 0) and not w.kin.is_alive(TRADER):
		var r: CardResultCommand = CardResultCommand.new()
		r.card = 0
		r.success = bluffing(w)
		PairHarness.send(w, r)


static func done(w: SimWorld) -> bool:
	return w.story.size() > 0 and not w.kin.is_alive(TRADER) and not Story.is_live(w, 0)


static func measure(w: SimWorld) -> Dictionary:
	return {
		"reputation": w.reputation.value_of(BLUE, RED),
		"reward": float(Economy.credits(w, PLAYER)),
	}


static func bluffing(w: SimWorld) -> bool:
	var row: int = w.knowledge.row_for(BLUE, TRADER)
	return row >= 0 and w.knowledge.intent[row] == KnowledgeTable.Intent.BLUFFING


## The crew without one link (a Link; -1 keeps all), a fresh one per run.
static func crew(removed: int = -1) -> Callable:
	var science: ScienceHand = ScienceHand.exact_from(PLAYER, TRADER, SCAN_AT)
	return func(w: SimWorld) -> void:
		if removed != Link.SCAN:
			science.act(w)
		if removed != Link.HEAR_CLAIM:
			hear_claim(w)
		if removed != Link.CALL_BLUFF:
			call_bluff(w)
		if removed != Link.ACT:
			act(w)


## Comms: hails the trader; its claim opens the conversation.
static func hear_claim(w: SimWorld) -> void:
	if w.tick == HAIL_TICK:
		var h: HailCommand = HailCommand.new()
		h.target = TRADER
		PairHarness.send(w, h)


## Comms: calls the bluff as soon as the option is open to it (the scan is in).
static func call_bluff(w: SimWorld) -> void:
	if w.tick <= HAIL_TICK or w.story.size() < 2 or w.story.node[1] != &"n0":
		return
	for o: Dictionary in Story.options(w, 1, 0):
		if o["id"] == &"o3" and o["enabled"]:
			var r: ReplyCommand = ReplyCommand.new()
			r.card = 1
			r.option = &"o3"
			PairHarness.send(w, r)


## Weapons: fires at the trader once its intent is BLUFFING.
static func act(w: SimWorld) -> void:
	if bluffing(w):
		Gunnery.gun(w, PLAYER, Gunnery.site_point(w, TRADER, Vector3.ZERO))
