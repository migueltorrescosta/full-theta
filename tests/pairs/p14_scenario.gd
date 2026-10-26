class_name P14Scenario
extends RefCounted
## P14 Science + Comms pair scenario (spec §7.4, FT-PAIR-015): the trader of the Bluff call
## (BluffScenario's world, conv.trader_bluff) claims to be harmless. "Call the bluff" is a
## reply that exists only once Science scanned its cargo (the scan fact "cargo").
## - Co-op: Science scans (ScienceHand, the average player's timing, scan time included in
##   the run); Comms hails the trader and calls the bluff once the option is open.
## - Solo: nobody scans; the option stays locked and Comms takes the trader's word (o1),
##   which ends the conversation with nothing gained (FT-PAIR-004).
## Metrics: reputation with the trader's faction and the replies a scan unlocked and Comms
## chose (the scan_option events, CoopEvents.SCAN_OPTION). The run ends when the
## conversation is over: the bluff called, or the claim accepted.

const PLAYER: int = BluffScenario.PLAYER
const TRADER: int = BluffScenario.TRADER
const BLUE: int = BluffScenario.BLUE
const RED: int = BluffScenario.RED
const TICK_LIMIT: int = 60 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, PairHarness.no_environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	return BluffScenario.build()


static func done(w: SimWorld) -> bool:
	return BluffScenario.bluffing(w) or (w.story.size() > 0 and not Story.is_live(w, 0))


static func measure(w: SimWorld) -> Dictionary:
	var unlocked: int = 0
	for e: SimEvent in w.events:
		if e.kind == &"scan_option":
			unlocked += 1
	return {"reputation": w.reputation.value_of(BLUE, RED), "unlocked": float(unlocked)}


## The option `id` of the hail card's open node, or {}.
static func option(w: SimWorld, id: StringName) -> Dictionary:
	if w.story.size() == 0 or w.story.node[0] == StoryTable.NO_TEXT:
		return {}
	for o: Dictionary in Story.options(w, 0):
		if o["id"] == id:
			return o
	return {}


## Science (a fresh script per run) and Comms, who calls the bluff when the option opens.
static func coop_crew() -> Callable:
	var science: ScienceHand = ScienceHand.exact_from(PLAYER, TRADER, BluffScenario.SCAN_AT)
	return func(w: SimWorld) -> void:
		science.act(w)
		_comms(w, true)


static func solo(w: SimWorld) -> void:
	_comms(w, false)


static func _comms(w: SimWorld, can_call: bool) -> void:
	if w.tick == BluffScenario.HAIL_TICK:
		var h: HailCommand = HailCommand.new()
		h.target = TRADER
		PairHarness.send(w, h)
	elif w.tick > BluffScenario.HAIL_TICK:
		var r: ReplyCommand = ReplyCommand.new()
		r.card = 0
		if can_call and option(w, &"o3").get("enabled", false):
			r.option = &"o3"
		elif not can_call and not option(w, &"o1").is_empty():
			r.option = &"o1"
		else:
			return
		PairHarness.send(w, r)
