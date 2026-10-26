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
## budget (D92). One encounter is open per ship; the next is picked a quiet gap after the
## last ended (D231). PROVISIONAL (Q4, Q14): the picking rules are placeholders for #13.

const LOW_HULL: float = 0.5
## Ticks a begin_encounter may stay unconfirmed before the director drops it as rejected.
const CONFIRM_TICKS: int = 3
## Site 0 is the home station (Kestrel Yard, D205): no encounter is placed there.
const HOME_SITE: int = 0

## Encounters a ship goes through before the run ends (RunDef.encounters); set by app/.
var encounters_per_run: int = 5

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
var _opened: int = 0
var _last_open_tick: int = 0
var _skip_logged: Dictionary[int, int] = {}


class ActiveRun:
	extends RefCounted
	var scenario: Scenario
	var api: ScenarioApi
	var encounter: int = -1
	var ship: int = -1
	var site: int = -1
	var issued_tick: int = 0
	var started: bool = false


func _init(
	def: DirectorDef, difficulty: StringName, catalogue: Array[Scenario], seed_value: int
) -> void:
	_def = def
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
	_step_runs(api, now)
	var crew: PackedInt32Array = api.crew_ships()
	_maybe_open_site(api, now)
	for ship: int in crew:
		_plan(api, now, ship)


## The decisions so far, oldest first.
func decisions() -> Array[DirectorDecision]:
	return _decisions


## Threat points left on the ship's budget.
func budget_left(ship: int) -> int:
	return _budget(ship) - _spent.get(ship, 0)


func _budget(_ship: int) -> int:
	return _def.budget_per_ship.get(_preset, 0)


func _cost_of(index: int) -> int:
	var meta: ScenarioMeta = _metas[index]
	return _def.costs.get(meta.id, meta.threat_cost)


## Starts, steps and ends the active scenarios; learns when their encounters are over.
func _step_runs(api: ScenarioApi, now: int) -> void:
	var keep: Array[ActiveRun] = []
	for run: ActiveRun in _runs:
		var ev: EncounterView = api.encounter(run.encounter)
		# An id predicted for a begin can land on another ship's encounter when an earlier
		# begin of the same tick is rejected: only ours counts.
		if ev.id >= 0 and (not ev.ships.has(run.ship) or ev.scenario_id != run.scenario.meta().id):
			ev = EncounterView.new()
		if ev.id < 0:
			# Not created: the command was rejected, or has not applied yet.
			if now - run.issued_tick < CONFIRM_TICKS:
				keep.append(run)
			else:
				_refund(run, now, "rejected")
			continue
		if ev.result > Scenario.Result.ACTIVE:
			_finished(api, run, now)
			continue
		if ev.result == Scenario.Result.ACTIVE:
			if not run.started:
				run.started = true
				run.scenario.start(run.api, {"site": ev.site, "ships": ev.ships})
			run.scenario.step(run.api)
			var result: int = run.scenario.finished(run.api)
			if result != Scenario.Result.ACTIVE:
				run.api.end_encounter(run.encounter, result)
		keep.append(run)
	_runs = keep


## The encounter ended (by its scenario, a flee or a loss): the ship rests for a gap.
func _finished(_api: ScenarioApi, run: ActiveRun, now: int) -> void:
	_done[run.ship] = _done.get(run.ship, 0) + 1
	_quiet_until[run.ship] = now + ceili(_def.gap_s * ScenarioApi.HZ)


## A rejected begin gives its cost back and the ship may be planned again.
func _refund(run: ActiveRun, now: int, reason: String) -> void:
	var cost: int = _cost_of(_index_of(run.scenario))
	var before: int = budget_left(run.ship)
	_spent[run.ship] = _spent.get(run.ship, 0) - cost
	_quiet_until[run.ship] = now + ceili(_def.gap_s * ScenarioApi.HZ)
	_log(
		now,
		run.ship,
		DirectorDecision.Kind.SKIP,
		{
			"scenario_id": _metas[_index_of(run.scenario)].id,
			"budget_before": before,
			"budget_after": budget_left(run.ship),
			"reason": reason,
		}
	)


func _plan(api: ScenarioApi, now: int, ship: int) -> void:
	if _busy(ship):
		return
	if _done.get(ship, 0) >= encounters_per_run:
		if not _ended_logged.has(ship):
			_ended_logged[ship] = true
			_log(
				now,
				ship,
				DirectorDecision.Kind.END_RUN,
				{
					"budget_before": budget_left(ship),
					"budget_after": budget_left(ship),
					"reason": "run_length",
					"args": {"encounters": _done[ship]},
				}
			)
		return
	if now < _quiet_until.get(ship, ceili(_def.gap_s * ScenarioApi.HZ)):
		return
	var view: ShipView = api.ship(ship)
	var fits: Array[int] = _fitting(ship)
	var reason: String = "budget_fits"
	if view.hull_frac < LOW_HULL:
		var calm: Array[int] = []
		calm.assign(fits.filter(func(i: int) -> bool: return not _metas[i].tags.has("hostile")))
		if not calm.is_empty():
			fits = calm
			reason = "low_hull"
	if fits.is_empty():
		_skip(now, ship)
		return
	var index: int = fits[_rng.randi() % fits.size()]
	var site: int = _site_for(api, now, ship)
	if site < 0:
		return
	_begin(api, now, ship, index, site, reason)


func _busy(ship: int) -> bool:
	for run: ActiveRun in _runs:
		if run.ship == ship:
			return true
	return false


## Catalogue indexes that fit the ship's budget, leaving out the last pick when another fits.
func _fitting(ship: int) -> Array[int]:
	var all: Array[int] = []
	var fresh: Array[int] = []
	for i: int in _catalogue.size():
		if _cost_of(i) > budget_left(ship):
			continue
		all.append(i)
		if _metas[i].id != _last_pick.get(ship, &""):
			fresh.append(i)
	return fresh if not fresh.is_empty() else all


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
			"budget_before": budget_left(ship),
			"budget_after": budget_left(ship),
			"reason": "no_fit",
		}
	)


## A site for the ship's next encounter: an open one with no encounter of ours, or, when
## none is free, one opened from the pool (logged); -1 when neither exists.
func _site_for(api: ScenarioApi, now: int, ship: int) -> int:
	var taken: Dictionary[int, bool] = {}
	for run: ActiveRun in _runs:
		taken[run.site] = true
	var free: Array[int] = []
	for s: SiteView in api.sites():
		if s.id != HOME_SITE and not taken.has(s.id):
			free.append(s.id)
	if not free.is_empty():
		return free[_rng.randi() % free.size()]
	return _open_one(api, now, ship, "site_pool")


## Opens a random closed site of the pool; returns its id or -1.
func _open_one(api: ScenarioApi, now: int, ship: int, reason: String) -> int:
	var pool: PackedStringArray = api.spawnable_sites()
	if pool.is_empty():
		return -1
	var key: StringName = StringName(pool[_rng.randi() % pool.size()])
	var id: int = api.open_site(key)
	_opened += 1
	_last_open_tick = now
	_log(
		now,
		ship,
		DirectorDecision.Kind.OPEN_SITE,
		{
			"site": id,
			"reason": reason,
			"args": {"site": String(key)},
		}
	)
	return id


## Opens a further site every spawn_site_every_s, up to max_open_sites (D80, FT-MIS-027).
func _maybe_open_site(api: ScenarioApi, now: int) -> void:
	if _def.spawn_site_every_s <= 0.0 or _opened >= _def.max_open_sites:
		return
	if now - _last_open_tick < ceili(_def.spawn_site_every_s * ScenarioApi.HZ):
		return
	_open_one(api, now, -1, "periodic")


func _begin(api: ScenarioApi, now: int, ship: int, index: int, site: int, reason: String) -> void:
	var meta: ScenarioMeta = _metas[index]
	var cost: int = _cost_of(index)
	var before: int = budget_left(ship)
	var run: ActiveRun = ActiveRun.new()
	run.scenario = _catalogue[index].fresh()
	run.ship = ship
	run.site = site
	run.issued_tick = now
	run.encounter = api.begin_encounter(meta.id, site, PackedInt32Array([ship]), cost)
	run.api = api.for_encounter(run.encounter)
	_runs.append(run)
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
			"budget_after": budget_left(ship),
			"reason": reason,
			"args": {"cost": cost, "left": budget_left(ship)},
		}
	)


func _index_of(scenario: Scenario) -> int:
	var id: StringName = scenario.meta().id
	for i: int in _metas.size():
		if _metas[i].id == id:
			return i
	return 0


func _log(now: int, ship: int, kind: DirectorDecision.Kind, f: Dictionary) -> void:
	var d: DirectorDecision = DirectorDecision.new()
	d.tick = now
	d.ship = ship
	d.kind = kind
	d.scenario_id = f.get("scenario_id", &"")
	d.site = f.get("site", -1)
	d.cost = f.get("cost", 0)
	d.budget_before = f.get("budget_before", 0)
	d.budget_after = f.get("budget_after", 0)
	d.reason_key = "director.reason.%s" % f["reason"]
	d.reason_args = f.get("args", {})
	_decisions.append(d)
