class_name BotCrew
extends RefCounted
## A scripted crew for one ship (FT-TST-022, based on tests/sim/run/scripted_crew.gd): before
## each tick, act() submits the commands the stations would send. Without a network, so it
## submits to the world directly and reads true state, as a crew with a radar lock would; it
## is deterministic for a seed. What it does, in order of priority:
## - fights: the nearest armed hostile within ENGAGE_REACH (unarmed debris within DEBRIS_REACH when
##   the profile shoots it), with the pips on the weapons, Face held, the lead aimed and shots
##   at the profile's cadence, from the mount whose arc holds the target (one Weapons player);
## - Relay: a decoy when a hostile targets the ship and the hull is under the profile's
##   decoy_hull; Comms: a call for help once the profile's help_hostiles are in play;
## - limps home: crippled in an active encounter (gp-09), with the propellant for a jump and
##   the profile willing, it jumps to the nearest dock, stops and docks within the time;
## - flees: below the profile's hull fraction, in an active encounter with a hostile in
##   sight, it faces Kestrel Yard and jumps (the sim then counts the encounter as fled);
## - travels: to the site of its pending encounter (the yard on a debris leg) by jump or by
##   impulse, undocking first, and holds there;
## - Comms: accepts cards by the profile, answers a hailing raider and demands its surrender;
## - Captain: picks one of a quiet gap's site offers (E2, w-bzx) by the fleet's hull.

const ENGAGE_REACH: float = 12000.0
const DEBRIS_REACH: float = 6000.0
const SHOOT_REACH: float = 5800.0
## The yard, site 0 (D205): where a fleeing crew goes and a debris leg ends.
const HOME: int = 0
const JUMP_AIM: float = 0.8
const NONE: int = -2

var profile: BotProfiles.Profile
var ship: int
## The current gap's site offers (RunDriver.site_offers of the crew's faction), a
## `func() -> Array[Dictionary]`; unset, the crew never picks.
var offers: Callable = Callable()

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seen: Dictionary[StringName, int] = {}
var _target: int = -1
var _pips_set: bool = false
var _going: int = NONE
var _by_jump: bool = true
var _jump_at: int = -1000
var _decided: Dictionary[int, bool] = {}
var _hail_stage: Dictionary[int, int] = {}
var _hail_at: Dictionary[int, int] = {}
var _moving: bool = false
## The mount the last aim went to; the shots follow it.
var _mount: int = 0
## The gap (its gap flag value) the crew last picked in (pick once per gap).
var _picked: int = -1


func _init(crew_profile: BotProfiles.Profile, ship_id: int, seed_value: int) -> void:
	profile = crew_profile
	ship = ship_id
	_rng.seed = seed_value


## Submits this tick's commands; call it right before the world steps.
func act(world: SimWorld) -> void:
	if not world.kin.is_alive(ship) or world.ships.status[ship] != ShipStateTable.Status.IN_PLAY:
		return
	if world.tick % profile.think_ticks != 0:
		return
	if profile.repairs and world.tick % profile.repair_every < profile.think_ticks:
		_repair(world)
	var target: int = _pick_target(world)
	var dock: int = _limp_site(world)
	if dock >= 0:
		_limp_home(world, dock)
	elif target >= 0 and _wants_flee(world):
		_flee(world)
	elif target >= 0:
		_going = NONE
		_fight(world, target)
	else:
		_clear(&"fight")
		_stand_down(world)
		_undock(world)
		_travel(world)
	_comms(world)
	_pick_site(world)
	if target >= 0:
		_decoy(world)
		_call_help(world)


# --- fighting ---


## The nearest hostile worth shooting that the crew's faction detects, or -1.
func _pick_target(world: SimWorld) -> int:
	var armed: int = KnowledgeSystem.nearest_hostile(world, ship, ENGAGE_REACH, true)
	if not profile.shoots_debris:
		return armed
	var any: int = KnowledgeSystem.nearest_hostile(world, ship, DEBRIS_REACH)
	if armed < 0:
		return any
	if any < 0:
		return armed
	return (
		any
		if world.kin.relative(ship, any).length() < world.kin.relative(ship, armed).length()
		else armed
	)


func _fight(world: SimWorld, target: int) -> void:
	if not _after(&"fight", world, profile.reaction_time):
		return
	if profile.sets_pips and not _pips_set:
		_pips_set = true
		var pips: SetPipsCommand = SetPipsCommand.new()
		pips.subsystem_kind = SubsystemDef.Kind.WEAPONS
		pips.pips = world.defs[ship].power.max_pips_per_subsystem
		_submit(world, pips)
	if target != _target:
		_target = target
		var select: HelmSelectCommand = HelmSelectCommand.new()
		select.contact = target
		_submit(world, select)
		_helm(world, true, false)
	var t: int = world.tick
	if t % profile.aim_every < profile.think_ticks:
		_aim(world, target)
	if t % profile.fire_every < profile.think_ticks:
		var d: float = world.kin.relative(ship, target).length()
		if d <= SHOOT_REACH and _rng.randf() >= profile.fire_skip:
			var fire: FireCommand = FireCommand.new()
			fire.mount_index = _mount
			_submit(world, fire)


## Aims the mount whose arc holds the target; the shots follow it.
func _aim(world: SimWorld, target: int) -> void:
	_mount = CrewMoves.mount_for(world, ship, target)
	_submit(world, CrewMoves.aim(world, ship, target, profile.aim_error, _rng, _mount))


## Relay's decoy: a hostile AI targets the ship, the hull is low and no decoy of the ship
## is out.
func _decoy(world: SimWorld) -> void:
	if DamageSystem.hull_fraction(world, ship) >= profile.decoy_hull:
		return
	if not ProbeSystem.can_decoy(world, ship) or _decoy_out(world):
		return
	for id: int in world.ship_count():
		if world.ai.is_enabled(id) and world.kin.is_alive(id) and world.ai.target[id] == ship:
			_submit(world, LaunchDecoyCommand.new())
			return


func _decoy_out(world: SimWorld) -> bool:
	var t: ProbeTable = world.probes
	for r: int in t.rows_of(ship):
		if t.decoy_left[r] > 0.0:
			return true
	return false


## Comms calls for help once enough hostiles are in play (CallHelp refuses a second call).
func _call_help(world: SimWorld) -> void:
	if profile.help_hostiles <= 0 or not CallHelp.can_call(world, ship):
		return
	var faction: int = world.faction_of(ship)
	var hostiles: int = 0
	for id: int in KnowledgeSystem.contacts(world, faction):
		if (
			world.kin.is_alive(id)
			and world.ai.is_enabled(id)
			and world.is_hostile(faction, world.faction_of(id))
		):
			hostiles += 1
	if hostiles >= profile.help_hostiles:
		_submit(world, CallHelpCommand.new())


## Lets go of the target: Face off, and stop if the crew has nothing else to fly to.
func _stand_down(world: SimWorld) -> void:
	if _target >= 0:
		_target = -1
		_helm(world, false, false)
		_submit(world, HelmSelectCommand.new())
		_moving = false
		_going = NONE


# --- Engineering ---


## Sends an idle repair crew to the most damaged subsystem no crew is working on.
func _repair(world: SimWorld) -> void:
	var dispatch: DispatchRepairCommand = CrewMoves.repair(world, ship)
	if dispatch != null:
		_submit(world, dispatch)


# --- fleeing and travelling ---


func _wants_flee(world: SimWorld) -> bool:
	if DamageSystem.hull_fraction(world, ship) >= profile.flee_hull:
		return false
	var enc: int = world.ships.encounter[ship]
	return enc >= 0 and world.encounters.result[enc] == EncounterTable.Result.ACTIVE


func _flee(world: SimWorld) -> void:
	_target = -1
	_go(world, HOME, true)


## The nearest dock a crippled crew can limp home to in time (gp-09), or -1: crippled in its
## active encounter less than RunDef.limp_home_time ago, with the propellant for one jump.
func _limp_site(world: SimWorld) -> int:
	var at: int = world.ships.crippled_tick[ship]
	if not profile.limps_home or at < 0 or world.run_def == null:
		return -1
	if world.tick > at + SimRate.ticks(world.run_def.limp_home_time):
		return -1
	if world.kin.propellant[ship] < world.defs[ship].jump_propellant:
		return -1
	var best: int = -1
	var best_d: float = INF
	for site: int in world.sites.size():
		if (
			not world.sites.dockable_of(site)
			or not world.sites.is_known(site, world.faction_of(ship))
		):
			continue
		var d: float = SiteTable.offset_to(world, ship, site).length()
		if d < best_d:
			best_d = d
			best = site
	return best


## Jumps to the dock when it is farther than a jump's standoff, flies the rest by impulse,
## then stops and docks.
func _limp_home(world: SimWorld, site: int) -> void:
	_target = -1
	var d: float = SiteTable.offset_to(world, ship, site).length()
	var near: float = world.sites.dock_range[site]
	if d > near:
		var far: bool = d > world.defs[ship].jump_standoff + near
		if _going == site and _by_jump == far:
			_go(world, site, far)
		else:
			# (a new plan, or the jump landed short: the last stretch by impulse)
			_going = NONE
			_go(world, site, far)
			_by_jump = far
			_helm(world, true, not far)
		return
	if _moving:
		_moving = false
		_helm(world, false, false)
		_submit(world, AllStopCommand.new())
	if world.kin.vel[ship].length() <= world.sites.dock_max_speed[site]:
		var dock: DockCommand = DockCommand.new()
		dock.site_id = site
		_submit(world, dock)


## Leaves the dock once the crew has an encounter elsewhere to go to (w-a89: a crew that
## limped home doesn't sit out the rest of the run at the dock, safe under D343).
func _undock(world: SimWorld) -> void:
	var docked: int = world.helm.docked_site[ship]
	var dest: int = _destination(world)
	if docked >= 0 and dest >= 0 and dest != docked:
		_submit(world, UndockCommand.new())


func _travel(world: SimWorld) -> void:
	var dest: int = _destination(world)
	if dest < 0:
		return
	if SiteTable.at_site(world, ship) == dest:
		if _moving:
			_moving = false
			_going = NONE
			_helm(world, false, false)
			_submit(world, AllStopCommand.new())
		return
	_go(world, dest, false)


## The site the crew is bound for: its pending or active encounter's, or the yard on a
## debris leg; -1 for none.
func _destination(world: SimWorld) -> int:
	var enc: int = world.ships.encounter[ship]
	if enc < 0:
		return -1
	var table: EncounterTable = world.encounters
	var ix: int = table.scenario_ix[enc]
	if ix >= 0 and world.scenario_ids[ix] == "debris_leg":
		return HOME if table.result[enc] == EncounterTable.Result.ACTIVE else table.site[enc]
	return table.site[enc]


## Heads for a site: select it, hold Face, then jump once the bow is on it, or hold Approach.
func _go(world: SimWorld, site: int, must_jump: bool) -> void:
	if _going != site:
		_going = site
		_by_jump = must_jump or _rng.randf() < profile.jump_share
		var select: HelmSelectCommand = HelmSelectCommand.new()
		select.site_id = site
		_submit(world, select)
		_helm(world, true, not _by_jump)
		_moving = true
		return
	if not _by_jump:
		return
	var def: ShipDef = world.defs[ship]
	var offset: Vector3 = SiteTable.offset_to(world, ship, site)
	if world.helm.jump_left[ship] > 0 or world.tick - _jump_at < 120 or not offset.is_finite():
		return
	if world.kin.forward(ship).angle_to(offset) <= def.jump_face_tolerance * JUMP_AIM:
		_jump_at = world.tick
		var jump: JumpCommand = JumpCommand.new()
		jump.target_kind = HelmTable.JumpKind.SITE
		jump.target_id = site
		_submit(world, jump)


# --- Comms ---


func _comms(world: SimWorld) -> void:
	var story: StoryTable = world.story
	for card: int in story.size():
		if not Story.visible_to(world, card, ship):
			continue
		var kind: int = story.kind[card]
		var state: int = story.state[card]
		# An answered hail is ACCEPTED, not OPEN: the surrender demand follows the answer
		# (review 2 L2).
		if kind == StoryTable.Kind.HAIL:
			var live: bool = state == StoryTable.State.OPEN or state == StoryTable.State.ACCEPTED
			if (
				live
				and profile.demands_surrender
				and story.conversation[card] == &"conv.surrender_demand"
			):
				_demand_surrender(world, card)
		elif state != StoryTable.State.OPEN or kind == StoryTable.Kind.INFO:
			continue  # an information card has nothing to accept (Q23)
		elif not _decided.has(card) and _after_card(world, card):
			_decided[card] = true
			if _accepts(story.title[card]):
				var accept: AcceptCardCommand = AcceptCardCommand.new()
				accept.card = card
				_submit(world, accept)


func _accepts(title: String) -> bool:
	match profile.accept:
		"escort":
			return title == "comms.card.escort" or title == "comms.card.lane_run"
		"random":
			return _rng.randf() < profile.accept_chance
	return false


## Answers the raider's hail, then asks it to surrender once the answer has been heard.
func _demand_surrender(world: SimWorld, card: int) -> void:
	var stage: int = _hail_stage.get(card, 0)
	var now: int = world.tick
	if stage == 0 and _after_card(world, card):
		_hail_stage[card] = 1
		_hail_at[card] = now
		var answer: AnswerHailCommand = AnswerHailCommand.new()
		answer.card = card
		_submit(world, answer)
	elif stage == 1 and now - _hail_at[card] >= 3 * SimWorld.HZ:
		_hail_stage[card] = 2
		var reply: ReplyCommand = ReplyCommand.new()
		reply.card = card
		reply.option = &"o1"
		_submit(world, reply)


# --- Captain ---


## Picks one of the gap's offers once per gap, comms_time after they appear: a logged
## SetFlagCommand on the faction's pick flag, the offer's index plus one.
func _pick_site(world: SimWorld) -> void:
	if not offers.is_valid():
		return
	var list: Array[Dictionary] = offers.call()
	if list.size() < 2:
		return
	var faction: int = world.faction_of(ship)
	var gap: int = world.story_flags.get_flag(Director.gap_flag(faction))
	if gap == _picked or not _after(StringName("pick %d" % gap), world, profile.comms_time):
		return
	_picked = gap
	var pick: int = choose(list, _fleet_hull(world), profile)
	var flag: SetFlagCommand = SetFlagCommand.new()
	flag.flag_name = Director.pick_flag(faction)
	flag.value = pick + 1
	world.submit(flag)  # a run-wide command, as the server's: no ship


## The offer a crew whose weakest ship is at hull fraction `hull` picks: bold, the best pay
## (then the lower risk); careful, the best pay less risk (then the lower risk); below that,
## the lowest risk (then the better pay). Further ties go to the lower index.
static func choose(list: Array[Dictionary], hull: float, p: BotProfiles.Profile) -> int:
	var best: int = 0
	var best_score: Vector2i = Vector2i(-1000, -1000)
	for i: int in list.size():
		var risk: int = list[i]["risk"]
		var pay: int = list[i]["reward"]
		var score: Vector2i = Vector2i(-risk, pay)
		if hull >= p.pick_bold_hull:
			score = Vector2i(pay, -risk)
		elif hull >= p.pick_careful_hull:
			score = Vector2i(pay - risk, -risk)
		if score > best_score:
			best_score = score
			best = i
	return best


## The lowest hull fraction among the faction's crewed ships in play.
func _fleet_hull(world: SimWorld) -> float:
	var faction: int = world.faction_of(ship)
	var low: float = 1.0
	for id: int in world.ship_count():
		if world.is_crew_in_play(id) and world.faction_of(id) == faction:
			low = minf(low, DamageSystem.hull_fraction(world, id))
	return low


# --- helpers ---


## Whether the situation `key` has stood for `seconds`; the clock starts the first time asked.
func _after(key: StringName, world: SimWorld, seconds: float) -> bool:
	if not _seen.has(key):
		_seen[key] = world.tick
	return world.tick - _seen[key] >= ceili(seconds * SimWorld.HZ)


func _after_card(world: SimWorld, card: int) -> bool:
	return _after(StringName("card%d" % card), world, profile.comms_time)


func _clear(key: StringName) -> void:
	_seen.erase(key)


func _helm(world: SimWorld, face: bool, approach: bool) -> void:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.face = face
	c.approach = approach
	_submit(world, c)


func _submit(world: SimWorld, command: SimCommand) -> void:
	command.ship_id = ship
	world.submit(command)
