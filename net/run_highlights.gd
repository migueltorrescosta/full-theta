class_name RunHighlights
extends RefCounted
## The three highlights of the end-of-run card (ux-20, FT-MIS-006), each by a fixed rule, kept
## by the server from what the sim reports each frame (the sim records none of them):
## - closest call: the lowest hull fraction a crewed ship reached while in play, and when (s);
##   left out when its hull never dropped, or when the ship was destroyed (the result says so);
## - top kill: the most valuable ship of another faction this ship destroyed (the largest
##   ShipDef.hull_max; the first one on a tie): its name and when;
## - best pair moment: the pair with the most cooperative events (CoopEvents.debrief; the
##   first in pair order on a tie), left out with none.
## A highlight with no data is left out of the record, not sent empty.

## Ship -> its lowest hull fraction so far and the run time it was reached (s).
var _low: Dictionary[int, Vector2] = {}
## Ship -> its top kill: {name, time, value}.
var _kill: Dictionary[int, Dictionary] = {}


## After the sim stepped (NetRunReset.after_ticks): the kills in `events` and every crewed ship
## still in play's hull, except the ships in `over` (their run has ended).
func sample(world: SimWorld, events: Array[SimEvent], over: Dictionary) -> void:
	for e: SimEvent in events:
		if e.kind != &"destroyed" or not world.has_ship(e.other_id):
			continue
		if not world.is_crew(e.other_id) or not world.has_ship(e.ship_id):
			continue
		if world.faction_of(e.ship_id) == world.faction_of(e.other_id):
			continue
		var def: ShipDef = world.defs[e.ship_id]
		if def.hull_max > float(_kill.get(e.other_id, {}).get("value", -1.0)):
			_kill[e.other_id] = {
				"name": def.display_name,
				"time": e.tick * SimWorld.DT,
				"value": def.hull_max,
			}
	var now: float = world.tick * SimWorld.DT
	for ship: int in world.ship_count():
		if over.has(ship) or not world.is_crew_in_play(ship):
			continue
		var hull: float = DamageSystem.hull_fraction(world, ship)
		if hull < _low.get(ship, Vector2(1.0, 0.0)).x:
			_low[ship] = Vector2(hull, now)


## The ship's highlights: {closest_call: {hull, time}, top_kill: {name, time},
## best_pair: {pair, stations, events}}, each only when it has data. `coop` is
## CoopEvents.debrief(); `destroyed` whether the ship ended at hull 0.
func for_ship(ship: int, coop: Array, destroyed: bool) -> Dictionary:
	var out: Dictionary = {}
	var low: Vector2 = _low.get(ship, Vector2(1.0, 0.0))
	if not destroyed and low.x < 1.0 and low.x > 0.0:
		out["closest_call"] = {"hull": low.x, "time": low.y}
	if _kill.has(ship):
		var k: Dictionary = _kill[ship]
		out["top_kill"] = {"name": k["name"], "time": k["time"]}
	var best: Dictionary = {}
	for row: Dictionary in coop:
		if int(row.get("events", 0)) > int(best.get("events", 0)):
			best = row
	if not best.is_empty():
		out["best_pair"] = {
			"pair": best["pair"], "stations": best["stations"], "events": best["events"]
		}
	return out
