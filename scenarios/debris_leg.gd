class_name DebrisLeg
extends Scenario
## A travel leg through debris (FT-MIS-041, D234): destructible debris contacts sit on the
## route to another named site and Weapons shoots them with the existing mounts as point
## defence; debris left in the way hurts through the collision rules (D119). The leg is the
## way home, from where the ship is to Kestrel Yard: traffic control warns the crew and offers
## a fee for the crossing. The encounter is won on reaching the yard, by impulse or by the
## jump drive (which flies past the debris), or when the time runs out. Only the Scenario API
## is used (FT-DAT-007).

const DEBRIS_FACTION: int = 4
const NPC: StringName = &"Traffic Control"
## Site 0, Kestrel Yard, where every leg ends (D205).
const HOME: int = 0
## Debris lies between this share of the leg and that one, within this much of the line (m).
const FIRST_T: float = 0.15
const LAST_T: float = 0.85
const LATERAL_M: float = 150.0
const FEE: int = 150
const MAX_S: float = 600.0

var _ship: int = -1
var _destination: int = -1
var _started: int = 0
var _done: bool = false


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"debris_leg"
	m.tags = PackedStringArray(["travel"])
	m.threat_cost = 0
	m.duration_s = MAX_S
	m.stations = PackedStringArray(["helm", "weapons"])
	m.branches = [
		{"id": "crossed", "outcome": "won"},
		{"id": "timeout", "outcome": "won"},
	]
	m.travel_hazard = &"debris"
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	var ships: PackedInt32Array = params["ships"]
	_ship = ships[0]
	_started = api.tick()
	var view: ShipView = api.ship(_ship)
	var from: int = view.nearest_site
	api.set_relation(DEBRIS_FACTION, view.faction, Relation.HOSTILE)
	_destination = HOME
	if from == HOME:
		_done = true
		return
	# The map names the leg's debris (MapDef.legs): an enemy key and how many pieces.
	for leg: Dictionary in api.legs():
		if leg["from"] != from or leg["to"] != _destination:
			continue
		var count: int = leg["count"]
		for i: int in count:
			var t: float = lerpf(FIRST_T, LAST_T, float(i) / maxi(count - 1, 1))
			var lateral: float = (api.rand(&"debris_leg") * 2.0 - 1.0) * LATERAL_M
			api.spawn_on_leg(leg["debris"], DEBRIS_FACTION, from, _destination, t, lateral)
	api.message("npc.lane_warning", {}, SayTarget.npc(NPC, _ship))
	var run: CardSpec = CardSpec.new()
	run.kind = CardSpec.Kind.MISSION
	run.npc_id = NPC
	run.title_key = &"comms.card.lane_run"
	run.conversation_id = &"conv.lane_run"
	run.reward_credits = FEE
	run.expires_s = MAX_S
	api.offer(_ship, run)


func step(api: ScenarioApi) -> void:
	if _done:
		return
	if api.ship(_ship).at_site == _destination:
		_done = true
		for c: CardView in api.cards_of(_ship):
			if c.title_key == "comms.card.lane_run" and c.state == CardView.State.ACCEPTED:
				api.settle_card(c.id, true)
	elif float(api.tick() - _started) / ScenarioApi.HZ >= MAX_S:
		_done = true


func finished(_api: ScenarioApi) -> int:
	return Result.WON if _done else Result.ACTIVE
