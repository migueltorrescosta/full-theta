class_name Director
extends RefCounted
## The encounter director (E07, FT-MIS-005, FT-MIS-006, FT-MIS-008, FT-MIS-025, FT-MIS-027,
## FT-MIS-028, FT-MIS-029, D35, D80, D81, D92, D231). Before each tick it reads the world
## through the Scenario API and queues SERVER commands: it opens sites, picks the next
## scenario for each idle crewed ship and steps the active scenarios. It changes which
## events occur and their parameters, never rules or stats (FT-MIS-005), and never holds
## the SimWorld: the API is its only door. Every decision is logged with its reason.
##
## The threat budget is per crewed ship: the DirectorDef's number for the difficulty
## preset, spent by the cost of each scenario picked for that ship. The preset is the name
## before ":" of the toggles code, so "normal:1011000" ("Normal (custom)") keeps Normal's
## budget (D92), and it sets the strength the scenarios scale their enemies by (Q14). One
## encounter is open per ship; the next is picked a quiet gap after the last ended (D231).
## A ship goes through RunDef.min_encounters to max_encounters of them (Q4, owner
## 2026-10-26): each pick leaves the budget for the fewest still to play, and the director
## closes the run (CloseRunCommand) when nothing fits any more or the most is reached.
## PROVISIONAL (Q4, Q14): the picking rules are placeholders for #13.
##
## Multi-ship sessions (#11, FT-MIS-023, M4-Q1, M4-Q5): FleetDirector makes one Director per
## crew faction. Such a Director plans for its faction's ships in play as one fleet: one
## budget, every encounter holding the whole fleet, its strength scaled to the fleet's size
## (fleet_multiplier), and one run closed for every ship at once. In a race it plays the
## seeded plan FleetDirector hands it (set_race) instead of picking, with no adaptation to
## the crew, each encounter at the ship's own copy of the site (ScenarioApi.open_site_copy).
## A single crewed ship is a fleet of one.

const LOW_HULL: float = 0.5
## Site 0 is the home station (Kestrel Yard, D205): no encounter is placed there.
const HOME_SITE: int = 0

## The event ScenarioApi.events() reports when RelaunchShipCommand puts a ship back in play
## (SessionOutcome.EVENT_RELAUNCHED; the director names sim/api only).
const RELAUNCHED: StringName = &"relaunched"

## The text of the Comms card that names a pending encounter's site (Q23).
const PENDING_DETAIL: StringName = &"card.encounter_pending.detail"

var _def: DirectorDef
var _preset: StringName
var _catalogue: Array[Scenario] = []
var _metas: Array[ScenarioMeta] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _decisions: Array[DirectorDecision] = []
var _spent: Dictionary[int, int] = {}
var _done: Dictionary[int, int] = {}
var _quiet_until: Dictionary[int, int] = {}
var _last_pick: Dictionary[int, StringName] = {}
var _ended_logged: Dictionary[int, bool] = {}
var _runs: Array[ActiveRun] = []
var _opening: Array[PendingOpen] = []
var _awaiting: Dictionary[int, PendingOpen] = {}
var _opened: int = 0
var _last_open_tick: int = 0
var _skip_logged: Dictionary[int, int] = {}
## The crew faction planned as one fleet. Every map above is keyed by it, the planning unit.
var _faction: int = -1
## The fleet's lowest ship id in play, named in the log.
var _lead: int = -1
## RACE: the plan, [{scenario, site}] in order (set_race); empty otherwise.
var _race: Array[Dictionary] = []
## Sites with an encounter of some director of the session (FleetDirector shares one set
## between its directors, so rival teams never share a site); a lone Director has its own.
var _taken: Dictionary[int, bool] = {}


class ActiveRun:
	extends RefCounted
	var scenario: Scenario
	## The begin_encounter write; `encounter` is its id once the command has applied.
	var handle: ApiHandle
	var encounter: int = -1
	var ship: int = -1
	var site: int = -1
	var started: bool = false


## An open_site write waiting to apply. A ship that picked a scenario but found no free site
## waits on it (`index`, `reason`); the periodic opens have ship -1.
class PendingOpen:
	extends RefCounted
	var handle: ApiHandle
	var ship: int = -1
	var key: StringName = &""
	var reason: String = ""
	var index: int = -1


func _init(
	def: DirectorDef,
	difficulty: StringName,
	catalogue: Array[Scenario],
	seed_value: int,
	faction: int
) -> void:
	_def = def
	_faction = faction
	_preset = preset_of(String(difficulty))
	_rng.seed = seed_value
	for s: Scenario in catalogue:
		var meta: ScenarioMeta = s.meta()
		if meta != null and not meta.training:
			_catalogue.append(s)
			_metas.append(meta)


## The difficulty preset a toggles code names: the part before ":", lower case (D92).
static func preset_of(code: String) -> StringName:
	return StringName(code.get_slice(":", 0).strip_edges().to_lower())


## Called by ScenarioHost before every tick.
func before_tick(api: ScenarioApi) -> void:
	var now: int = api.tick()
	_resolve_opens(now)
	_step_runs(api, now)
	_on_relaunches(api)
	var fleet: PackedInt32Array = api.crew_ships_of(_faction)
	if _race.is_empty():
		_maybe_open_site(api, now)
	if not fleet.is_empty():
		_lead = fleet[0]
		_plan(api, now, _faction)


## A fleet ship relaunched (D259: a fresh ship with a fresh run state) must go through the
## run's encounters itself, or CloseRunCommand would refuse it: the fleet's plan starts over,
## its budget, count, quiet time and closed run forgotten.
func _on_relaunches(api: ScenarioApi) -> void:
	for e: ApiEvent in api.events():
		if e.kind == RELAUNCHED and api.faction_of(e.ship_id) == _faction:
			_spent.erase(_faction)
			_done.erase(_faction)
			_quiet_until.erase(_faction)
			_last_pick.erase(_faction)
			_ended_logged.erase(_faction)
			_skip_logged.erase(_faction)


## Makes this Director leave the sites in `taken` alone and record its own there (FleetDirector
## shares one between its directors).
func share_sites(taken: Dictionary[int, bool]) -> void:
	_taken = taken


## The strength multiplier of an encounter holding `ships` crewed ships (FT-MIS-023, M4-Q1):
## DirectorDef.fleet_strength_per_ship more for each ship beyond the first.
static func fleet_multiplier(def: DirectorDef, ships: int) -> float:
	return 1.0 + def.fleet_strength_per_ship * maxi(ships - 1, 0)


## RACE (M4-Q5): plays `plan` in order instead of picking.
func set_race(plan: Array[Dictionary]) -> void:
	_race = plan


## RACE (M4-Q5): one encounter list for every ship, drawn once with this director's seed: up to
## the most encounters a run allows, each fitting the preset's budget and leaving enough of it
## for the fewest still to play, like the picks of one ship that never adapts (no low-hull
## swap), and each at a site of `site_keys`; never fewer than the fewest a run needs. Travel
## legs are left out, as they end at Kestrel Yard rather than at a ship's own copy of it.
## Entries are {scenario, site} (ids and keys).
func plan_race(limits: Vector2i, site_keys: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var usable: Array[int] = []
	for i: int in _catalogue.size():
		if _metas[i].travel_hazard == &"":
			usable.append(i)
	if usable.is_empty():
		return out
	var left: int = _budget()
	var last: StringName = &""
	while out.size() < limits.y:
		var fits: Array[int] = _affordable(usable, left, out.size(), limits.x, last)
		if fits.is_empty():
			break
		var index: int = fits[_rng.randi() % fits.size()]
		var site: String = ""
		if not site_keys.is_empty():
			site = site_keys[_rng.randi() % site_keys.size()]
		out.append({"scenario": _metas[index].id, "site": StringName(site)})
		left -= _cost_of(index)
		last = _metas[index].id
	return out


## The decisions so far, oldest first.
func decisions() -> Array[DirectorDecision]:
	return _decisions


## Threat points left on the fleet's budget.
func budget_left() -> int:
	return _left(_faction)


func _left(unit: int) -> int:
	return _budget() - _spent.get(unit, 0)


func _budget() -> int:
	return _def.budget_per_ship.get(_preset, 0)


func _cost_of(index: int) -> int:
	var meta: ScenarioMeta = _metas[index]
	return meta.threat_cost


## The cheapest of the catalogue indexes `candidates` (at least 1: every scenario costs at
## least 1, so the reserve always counts the encounters still to play), or -1 for none.
func _cheapest_of(candidates: Array[int]) -> int:
	var best: int = -1
	for i: int in candidates:
		if best < 0 or _cost_of(i) < _cost_of(best):
			best = i
	return best


## The shared budget rule of a pick and of a race plan: the `candidates` that fit `left` and
## leave enough of it for the fewest encounters still to play (each costs at least the
## cheapest candidate), leaving out the last pick when another fits. With `done` below
## `fewest` and nothing fitting, the cheapest goes in even over the budget, so a run can
## always be finished (the empty result means nothing is playable, or enough has been).
func _affordable(
	candidates: Array[int], left: int, done: int, fewest: int, last: StringName
) -> Array[int]:
	var cheapest: int = _cheapest_of(candidates)
	var all: Array[int] = []
	var fresh: Array[int] = []
	if cheapest >= 0:
		var reserve: int = maxi(0, fewest - done - 1) * maxi(1, _cost_of(cheapest))
		for i: int in candidates:
			if _cost_of(i) > left - reserve:
				continue
			all.append(i)
			if _metas[i].id != last:
				fresh.append(i)
	var fits: Array[int] = fresh if not fresh.is_empty() else all
	if fits.is_empty() and cheapest >= 0 and done < fewest:
		fits = [cheapest]
	return fits


## Starts, steps and ends the active scenarios; learns when their encounters are over.
func _step_runs(api: ScenarioApi, now: int) -> void:
	var keep: Array[ActiveRun] = []
	for run: ActiveRun in _runs:
		if run.encounter < 0:
			# The begin applies on the next tick; its handle then holds the real id (Q24), or
			# says it was rejected (the ship was in another encounter, review 2 M4).
			if run.handle.pending():
				keep.append(run)
				continue
			if run.handle.rejected():
				_refund(run, now)
				continue
			run.encounter = run.handle.id()
		var ev: EncounterView = api.encounter(run.encounter)
		if ev.result > Scenario.Result.ACTIVE:
			if run.started:
				run.scenario.end(api, ev.result)
			_finished(run, now)
			continue
		if ev.result == Scenario.Result.ACTIVE:
			if not run.started:
				run.started = true
				(
					run
					. scenario
					. start(
						api,
						{
							"site": ev.site,
							"ships": ev.ships,
							"strength": _strength() * fleet_multiplier(_def, ev.ships.size()),
						},
					)
				)
			run.scenario.step(api)
			var result: int = run.scenario.finished(api)
			if result != Scenario.Result.ACTIVE:
				api.end_encounter(run.encounter, result)
		keep.append(run)
	_runs = keep


## The encounter ended (by its scenario, a flee or a loss): the ship rests for a gap.
func _finished(run: ActiveRun, now: int) -> void:
	_taken.erase(run.site)
	_done[run.ship] = _done.get(run.ship, 0) + 1
	_quiet_until[run.ship] = now + ScenarioApi.ticks(_def.gap_s)


## A rejected begin gives its cost back and the ship may be planned again.
func _refund(run: ActiveRun, now: int) -> void:
	_taken.erase(run.site)
	var cost: int = _cost_of(_index_of_id(run.scenario.meta().id))
	var before: int = _left(run.ship)
	_spent[run.ship] = _spent.get(run.ship, 0) - cost
	_quiet_until[run.ship] = now + ScenarioApi.ticks(_def.gap_s)
	_log(
		now,
		run.ship,
		DirectorDecision.Kind.SKIP,
		{
			"scenario_id": run.scenario.meta().id,
			"budget_before": before,
			"budget_after": _left(run.ship),
			"reason": "rejected",
		}
	)


func _plan(api: ScenarioApi, now: int, ship: int) -> void:
	if _awaiting.has(ship):
		_begin_when_open(api, now, ship)
		return
	if _busy(ship) or _ended_logged.has(ship):
		return
	var limits: Vector2i = api.encounter_limits()
	if _done.get(ship, 0) >= limits.y:
		_close_run(api, now, ship, "run_length")
		return
	if now >= _quiet_until.get(ship, ScenarioApi.ticks(_def.gap_s)):
		_pick(api, now, ship, limits.x)


## Picks the ship's next scenario and a site for it, or closes the run when nothing fits.
func _pick(api: ScenarioApi, now: int, ship: int, fewest: int) -> void:
	if not _race.is_empty():
		_pick_race(api, now, ship)
		return
	var hull: float = 1.0
	for s: int in _ships(api):
		hull = minf(hull, api.ship(s).hull_frac)
	var everything: Array[int] = []
	for i: int in _catalogue.size():
		everything.append(i)
	var fits: Array[int] = _affordable(
		everything, _left(ship), _done.get(ship, 0), fewest, _last_pick.get(ship, &"")
	)
	var reason: String = "budget_fits"
	if hull < LOW_HULL:
		var calm: Array[int] = []
		calm.assign(fits.filter(func(i: int) -> bool: return not _metas[i].tags.has("hostile")))
		if not calm.is_empty():
			fits = calm
			reason = "low_hull"
	if fits.is_empty():
		# Nothing fits the budget: the run ends once the fewest encounters are played. An
		# empty catalogue has nothing to play, which is logged once.
		if _done.get(ship, 0) >= fewest:
			_close_run(api, now, ship, "budget_spent")
		else:
			_skip(now, ship)
		return
	var index: int = fits[_rng.randi() % fits.size()]
	var site: int = _free_site(api)
	if site < 0:
		# No site is open and free: open one from the pool and begin when it exists.
		var pending: PendingOpen = _open_one(api, now, ship, "site_pool")
		if pending == null:
			return
		pending.index = index
		pending.reason = reason
		_awaiting[ship] = pending
		return
	_begin(api, now, ship, index, site, reason)


## RACE: the plan's next encounter at the ship's own copy of its site, or the run's close
## once the plan is played.
func _pick_race(api: ScenarioApi, now: int, unit: int) -> void:
	var done: int = _done.get(unit, 0)
	if done >= _race.size():
		var reason: String = "run_length" if done >= api.encounter_limits().y else "budget_spent"
		_close_run(api, now, unit, reason)
		return
	var entry: Dictionary = _race[done]
	var index: int = _index_of_id(entry["scenario"])
	if entry["site"] == &"":
		_begin(api, now, unit, index, -1, "budget_fits")
		return
	var pending: PendingOpen = PendingOpen.new()
	pending.handle = api.open_site_copy(entry["site"], _lead)
	pending.ship = unit
	pending.index = index
	pending.reason = "budget_fits"
	_awaiting[unit] = pending
	_begin_when_open(api, now, unit)


## The ship waits for the site it asked to open: begin there once it exists.
func _begin_when_open(api: ScenarioApi, now: int, ship: int) -> void:
	var pending: PendingOpen = _awaiting[ship]
	if pending.handle.pending():
		return
	_awaiting.erase(ship)
	if pending.handle.rejected():
		return
	_begin(api, now, ship, pending.index, pending.handle.id(), pending.reason)


func _busy(ship: int) -> bool:
	for run: ActiveRun in _runs:
		if run.ship == ship:
			return true
	return false


## Closes the ship's run once (CloseRunCommand), for every ship of a fleet, and logs why.
func _close_run(api: ScenarioApi, now: int, ship: int, reason: String) -> void:
	_ended_logged[ship] = true
	for s: int in _ships(api):
		api.close_run(s)
	_log(
		now,
		ship,
		DirectorDecision.Kind.END_RUN,
		{
			"budget_before": _left(ship),
			"budget_after": _left(ship),
			"reason": reason,
			"args": {"encounters": _done.get(ship, 0)},
		}
	)


## The enemy-strength multiplier of the difficulty preset (Q14, DirectorDef).
func _strength() -> float:
	return preset_strength(_def, _preset)


## The enemy-strength multiplier the toggles code's preset names (1.0 for a preset the def
## doesn't list).
static func preset_strength(def: DirectorDef, difficulty: StringName) -> float:
	return def.strength_per_preset.get(preset_of(String(difficulty)), 1.0)


## Logs once per quiet period that nothing fits the budget.
func _skip(now: int, ship: int) -> void:
	if _skip_logged.get(ship, -1) == _done.get(ship, 0):
		return
	_skip_logged[ship] = _done.get(ship, 0)
	_log(
		now,
		ship,
		DirectorDecision.Kind.SKIP,
		{
			"budget_before": _left(ship),
			"budget_after": _left(ship),
			"reason": "no_fit",
		}
	)


## An open site with no encounter of the session's directors, or -1 when none is free.
func _free_site(api: ScenarioApi) -> int:
	var free: Array[int] = []
	for s: SiteView in api.sites():
		if s.id != HOME_SITE and not _taken.has(s.id):
			free.append(s.id)
	return free[_rng.randi() % free.size()] if not free.is_empty() else -1


## Queues the opening of a random closed site of the pool; null when the pool is empty. The
## site's id is known after the tick (_resolve_opens logs it).
func _open_one(api: ScenarioApi, now: int, ship: int, reason: String) -> PendingOpen:
	var pool: PackedStringArray = api.spawnable_sites()
	if pool.is_empty():
		return null
	var pending: PendingOpen = PendingOpen.new()
	pending.key = StringName(pool[_rng.randi() % pool.size()])
	pending.ship = ship
	pending.reason = reason
	pending.handle = api.open_site(pending.key)
	_opening.append(pending)
	_opened += 1
	_last_open_tick = now
	return pending


## Logs each site opened since the last tick, now that it has an id.
func _resolve_opens(now: int) -> void:
	var waiting: Array[PendingOpen] = []
	for pending: PendingOpen in _opening:
		if pending.handle.pending():
			waiting.append(pending)
		elif not pending.handle.rejected():
			_log(
				now,
				pending.ship,
				DirectorDecision.Kind.OPEN_SITE,
				{
					"site": pending.handle.id(),
					"reason": pending.reason,
					"args": {"site": String(pending.key)},
				}
			)
	_opening = waiting


## Opens a further site every spawn_site_every_s, up to max_open_sites (D80, FT-MIS-027).
func _maybe_open_site(api: ScenarioApi, now: int) -> void:
	if _def.spawn_site_every_s <= 0.0 or _opened >= _def.max_open_sites or not _race.is_empty():
		return
	if now - _last_open_tick < ScenarioApi.ticks(_def.spawn_site_every_s):
		return
	_open_one(api, now, -1, "periodic")


func _begin(api: ScenarioApi, now: int, ship: int, index: int, site: int, reason: String) -> void:
	var meta: ScenarioMeta = _metas[index]
	var cost: int = _cost_of(index)
	var before: int = _left(ship)
	var run: ActiveRun = ActiveRun.new()
	run.scenario = _catalogue[index].fresh()
	run.ship = ship
	run.site = site
	if site >= 0:
		_taken[site] = true
	var ships: PackedInt32Array = _ships(api)
	run.handle = api.begin_encounter(meta.id, site, ships, cost)
	_runs.append(run)
	for s: int in ships:
		_announce_site(api, s, site)
	_spent[ship] = _spent.get(ship, 0) + cost
	_last_pick[ship] = meta.id
	_log(
		now,
		ship,
		DirectorDecision.Kind.PICK_ENCOUNTER,
		{
			"scenario_id": meta.id,
			"site": site,
			"cost": cost,
			"budget_before": before,
			"budget_after": _left(ship),
			"reason": reason,
			"args": {"cost": cost, "left": _left(ship)},
		}
	)


## Q23 (owner, 2026-10-26): only a Comms card names a pending encounter's site (D231); Comms
## relays it to Helm. BeginEncounterCommand has already revealed the site to the ship's
## faction, so Helm can select and jump to it. The card only informs (CardSpec.Kind.INFO)
## and lapses when the arrival timeout starts the encounter anyway.
func _announce_site(api: ScenarioApi, ship: int, site: int) -> void:
	var name_key: String = ""
	for s: SiteView in api.sites():
		if s.id == site:
			name_key = s.name_key
	if name_key == "":
		return
	var card: CardSpec = CardSpec.new()
	card.kind = CardSpec.Kind.INFO
	card.title_key = StringName(name_key)
	card.detail_key = PENDING_DETAIL
	card.expires_s = _def.arrival_timeout_s
	api.offer(ship, card)


## The fleet's crewed ships in play.
func _ships(api: ScenarioApi) -> PackedInt32Array:
	return api.crew_ships_of(_faction)


func _index_of_id(id: StringName) -> int:
	for i: int in _metas.size():
		if _metas[i].id == id:
			return i
	assert(false, "scenario %s is not in the catalogue" % id)
	return 0


func _log(now: int, ship: int, kind: DirectorDecision.Kind, f: Dictionary) -> void:
	var d: DirectorDecision = DirectorDecision.new()
	d.tick = now
	d.ship = _lead if ship == _faction else ship
	d.kind = kind
	d.scenario_id = f.get("scenario_id", &"")
	d.site = f.get("site", -1)
	d.cost = f.get("cost", 0)
	d.budget_before = f.get("budget_before", 0)
	d.budget_after = f.get("budget_after", 0)
	d.reason_key = "director.reason.%s" % f["reason"]
	d.reason_args = f.get("args", {})
	_decisions.append(d)
