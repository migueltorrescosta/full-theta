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

const LOW_HULL: float = 0.5
## Site 0 is the home station (Kestrel Yard, D205): no encounter is placed there.
const HOME_SITE: int = 0

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
	_resolve_opens(now)
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
		if run.encounter < 0:
			# The begin applies on the next tick; its handle then holds the real id (Q24), or
			# says it was rejected (the ship was in another encounter, review 2 M4).
			if run.handle.pending():
				keep.append(run)
				continue
			if run.handle.rejected():
				_refund(run, now, "rejected")
				continue
			run.encounter = run.handle.id()
		var ev: EncounterView = api.encounter(run.encounter)
		if ev.result > Scenario.Result.ACTIVE:
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
						{"site": ev.site, "ships": ev.ships, "strength": _strength()},
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
	if _awaiting.has(ship):
		_begin_when_open(api, now, ship)
		return
	if _busy(ship) or _ended_logged.has(ship):
		return
	var limits: Vector2i = api.encounter_limits()
	if _done.get(ship, 0) >= limits.y:
		_close_run(api, now, ship, "run_length")
		return
	if now >= _quiet_until.get(ship, ceili(_def.gap_s * ScenarioApi.HZ)):
		_pick(api, now, ship, limits.x)


## Picks the ship's next scenario and a site for it, or closes the run when nothing fits.
func _pick(api: ScenarioApi, now: int, ship: int, fewest: int) -> void:
	var view: ShipView = api.ship(ship)
	var fits: Array[int] = _fitting(ship, fewest)
	var reason: String = "budget_fits"
	if view.hull_frac < LOW_HULL:
		var calm: Array[int] = []
		calm.assign(fits.filter(func(i: int) -> bool: return not _metas[i].tags.has("hostile")))
		if not calm.is_empty():
			fits = calm
			reason = "low_hull"
	if fits.is_empty():
		# Nothing fits the budget: the run ends once the fewest encounters are played.
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


## Closes the ship's run once (CloseRunCommand) and logs why.
func _close_run(api: ScenarioApi, now: int, ship: int, reason: String) -> void:
	_ended_logged[ship] = true
	api.close_run(ship)
	_log(
		now,
		ship,
		DirectorDecision.Kind.END_RUN,
		{
			"budget_before": budget_left(ship),
			"budget_after": budget_left(ship),
			"reason": reason,
			"args": {"encounters": _done.get(ship, 0)},
		}
	)


## Catalogue indexes that fit the ship's budget and leave enough of it for the fewest
## encounters still to play (each costs at least the cheapest scenario), leaving out the last
## pick when another fits.
func _fitting(ship: int, fewest: int) -> Array[int]:
	var all: Array[int] = []
	var fresh: Array[int] = []
	var reserve: int = maxi(0, fewest - _done.get(ship, 0) - 1) * _cheapest()
	for i: int in _catalogue.size():
		if _cost_of(i) > budget_left(ship) - reserve:
			continue
		all.append(i)
		if _metas[i].id != _last_pick.get(ship, &""):
			fresh.append(i)
	return fresh if not fresh.is_empty() else all


func _cheapest() -> int:
	var least: int = 1
	for i: int in _catalogue.size():
		least = _cost_of(i) if i == 0 else mini(least, _cost_of(i))
	return maxi(1, least)


## The enemy-strength multiplier of the difficulty preset (Q14, DirectorDef).
func _strength() -> float:
	return _def.strength_per_preset.get(_preset, 1.0)


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


## An open site with no encounter of ours, or -1 when none is free.
func _free_site(api: ScenarioApi) -> int:
	var taken: Dictionary[int, bool] = {}
	for run: ActiveRun in _runs:
		taken[run.site] = true
	var free: Array[int] = []
	for s: SiteView in api.sites():
		if s.id != HOME_SITE and not taken.has(s.id):
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
	run.handle = api.begin_encounter(meta.id, site, PackedInt32Array([ship]), cost)
	_runs.append(run)
	_announce_site(api, ship, site)
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


## PROVISIONAL (Q23): only a Comms card names a pending encounter's site (D231); Comms
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
