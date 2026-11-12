class_name DebrisLeg
extends Scenario
## A travel leg through debris (FT-MIS-041, D234): destructible debris contacts sit on the
## route to another named site and Weapons shoots them with the existing mounts as point
## defence; debris left in the way hurts through the collision rules (D119). The leg is the
## way home, from the encounter's site to Kestrel Yard: traffic control warns the crew and
## offers a docking clearance for the crossing (P5): accepted, it opens an approach lane to the
## yard (a window on Helm's route), and docking inside it pays the fee while docking before or
## after it costs standing (StoryRules.on_dock). The encounter is won on reaching the yard after
## having been away from it, by impulse or by the jump drive (which flies past the debris); a
## ship still at the yard when the encounter starts has not crossed anything (review 2 M5). When
## the time runs out first it ends as partial (#35 A3), and an undocked clearance lapses unpaid.
## The whole fleet is served (A2): the clearance card is faction-wide and the leg is won when
## any ship still in the fight reaches the yard after having left it; the ship that docks in
## the lane is paid. A leg that ends by a flee or a loss fails its accepted clearance (A8).
## Only the Scenario API is used (FT-DAT-007).

const NPC: StringName = &"Traffic Control"
## Site 0, Kestrel Yard, where every leg ends (D205).
const HOME: int = 0
## Debris lies between this share of the leg and that one, within this much of the line (m).
const FIRST_T: float = 0.15
const LAST_T: float = 0.85
const LATERAL_M: float = 150.0
const FEE: int = 150
## The clearance's lane opens this long after the card is accepted and stays open this long
## (s); the card lapses at MAX_S.
const LANE_OPEN_S: float = 30.0
const LANE_S: float = 540.0
## The civil faction whose standing an uncleared approach costs (rescue's freighters, too).
const MAX_S: float = 600.0
## The fee card outlasts the encounter, so a timeout can still settle it.
const CARD_S: float = MAX_S + 30.0

var _ships: PackedInt32Array = PackedInt32Array()
var _destination: int = -1
var _started: int = 0
## The ships that have been away from the yard since the encounter started.
var _left: Dictionary[int, bool] = {}
var _clearance: ApiHandle
var _result: int = Result.ACTIVE


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"debris_leg"
	m.tags = PackedStringArray(["travel"])
	m.threat_cost = 1
	m.travel_hazard = &"debris"
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	_ships = params["ships"]
	var lead: int = Scenario.fleet(api, _ships)[0]
	_started = api.tick()
	var view: ShipInfo = api.ship(lead)
	var from: int = params.get("site", view.nearest_site)
	api.set_relation(Factions.DEBRIS, view.faction, Relation.HOSTILE)
	_destination = HOME
	if from == HOME:
		_result = Result.WON
		return
	# The map names the leg's debris (MapDef.legs): an NPC key and how many pieces.
	for leg: Dictionary in api.legs():
		if leg["from"] != from or leg["to"] != _destination:
			continue
		var count: int = leg["count"]
		for i: int in count:
			var t: float = lerpf(FIRST_T, LAST_T, float(i) / maxi(count - 1, 1))
			var lateral: float = (api.rand(&"debris_leg") * 2.0 - 1.0) * LATERAL_M
			api.spawn_on_leg(leg["debris"], Factions.DEBRIS, from, _destination, t, lateral)
	for ship: int in Scenario.fleet(api, _ships):
		api.message("npc.lane_warning", {}, LineAudience.npc(NPC, ship))
	var run: CardSpec = CardSpec.new()
	run.kind = CardSpec.Kind.CONTRACT
	run.npc_id = NPC
	run.title_key = &"comms.card.lane_run"
	run.conversation_id = &"conv.lane_run"
	run.reward_credits = FEE
	run.expiry = MAX_S
	run.site = HOME
	run.lane_delay = LANE_OPEN_S
	run.lane_length = LANE_S
	run.rep_faction = Factions.CIVIL
	run.faction_wide = true
	_clearance = api.offer(lead, run)


func step(api: ScenarioApi) -> void:
	if _result != Result.ACTIVE:
		return
	for ship: int in Scenario.fleet(api, _ships):
		var at: int = api.at_site(ship)
		if at != _destination:
			_left[ship] = true
		elif _left.has(ship):
			_result = Result.WON
			return
	if Scenario.timed_out(api, _started, MAX_S):
		_result = Result.PARTIAL


func finished(_api: ScenarioApi) -> int:
	return _result


## A leg ended by a flee or a loss (not by itself) fails an accepted clearance, so a later dock
## in its lane pays no fee, and withdraws one nobody accepted (A8).
func end(api: ScenarioApi, result: int) -> void:
	if _clearance == null or _clearance.id() < 0:
		return
	var state: int = CardInfo.State.EXPIRED
	for c: CardInfo in api.cards_of(Scenario.fleet(api, _ships)[0]):
		if c.id == _clearance.id():
			state = c.state
	if state == CardInfo.State.ACCEPTED and _result == Result.ACTIVE:
		api.settle_card(_clearance.id(), false)
	elif state == CardInfo.State.OPEN:
		api.decline_card(_clearance.id())
	if _result == Result.ACTIVE:
		_result = result
