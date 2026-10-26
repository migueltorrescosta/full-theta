class_name BotCrew
extends RefCounted
## A scripted crew for one ship (FT-TST-022, based on tests/sim/run/scripted_crew.gd): before
## each tick, act() submits the commands the stations would send. Without a network, so it
## submits to the world directly and reads true state, as a crew with a radar lock would; it
## is deterministic for a seed. What it does, in order of priority:
## - fights: the nearest armed hostile within ENGAGE_M (unarmed debris within DEBRIS_M when
##   the profile shoots it), with the pips on the weapons, Face held, the lead aimed and shots
##   at the profile's cadence;
## - flees: below the profile's hull fraction, in an active encounter with a hostile in
##   sight, it faces Kestrel Yard and jumps (the sim then counts the encounter as fled);
## - travels: to the site of its pending encounter (the yard on a debris leg) by jump or by
##   impulse, and holds there;
## - Comms: accepts cards by the profile, answers a hailing raider and demands its surrender.

const ENGAGE_M: float = 12000.0
const DEBRIS_M: float = 6000.0
const SHOOT_M: float = 5800.0
## The yard, site 0 (D205): where a fleeing crew goes and a debris leg ends.
const HOME: int = 0
const JUMP_AIM: float = 0.8
const NONE: int = -2

var profile: BotProfiles.Profile
var ship: int

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


func _init(crew_profile: BotProfiles.Profile, ship_id: int, seed_value: int) -> void:
	profile = crew_profile
	ship = ship_id
	_rng.seed = seed_value


## Submits this tick's commands; call it right before the world steps.
func act(world: SimWorld) -> void:
	if not world.kin.is_alive(ship) or world.run.status[ship] != RunTable.Status.IN_PLAY:
		return
	if world.tick % profile.think_ticks != 0:
		return
	if profile.repairs and world.tick % profile.repair_every < profile.think_ticks:
		_repair(world)
	var target: int = _pick_target(world)
	if target >= 0 and _wants_flee(world):
		_flee(world)
	elif target >= 0:
		_going = NONE
		_fight(world, target)
	else:
		_clear(&"fight")
		_stand_down(world)
		_travel(world)
	_comms(world)


# --- fighting ---


## The nearest hostile worth shooting that the crew's faction detects, or -1.
func _pick_target(world: SimWorld) -> int:
	var faction: int = world.faction_of(ship)
	var best: int = -1
	var best_d: float = INF
	for id: int in world.ship_count():
		if id == ship or not world.ai.is_enabled(id) or not world.kin.is_alive(id):
			continue
		if world.run.status[id] != RunTable.Status.IN_PLAY:
			continue
		if world.relation(faction, world.faction_of(id)) != SimWorld.Relation.HOSTILE:
			continue
		if not KnowledgeSystem.is_detected(world, faction, id):
			continue
		var d: float = world.kin.relative(ship, id).length()
		var armed: bool = not world.defs[id].mounts.is_empty()
		if d > (ENGAGE_M if armed else DEBRIS_M) or (not armed and not profile.shoots_debris):
			continue
		if d < best_d:
			best = id
			best_d = d
	return best


func _fight(world: SimWorld, target: int) -> void:
	if not _after(&"fight", world, profile.reaction_s):
		return
	if profile.sets_pips and not _pips_set:
		_pips_set = true
		var pips: SetPipsCommand = SetPipsCommand.new()
		pips.subsystem_kind = SubsystemDef.Kind.WEAPONS
		pips.pips = world.defs[ship].power.max_pips_per_subsystem
		_submit(world, pips)
	if target != _target:
		_target = target
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.target_ship = target
		_submit(world, select)
		_helm(world, true, false)
	var t: int = world.tick
	if t % profile.aim_every < profile.think_ticks:
		_aim(world, target)
	if t % profile.fire_every < profile.think_ticks:
		var d: float = world.kin.relative(ship, target).length()
		if d <= SHOOT_M and _rng.randf() >= profile.fire_skip:
			_submit(world, FireCommand.new())


func _aim(world: SimWorld, target: int) -> void:
	var kin: Kinematics = world.kin
	var aim: Vector3 = EnemyAi.lead_aim(world, ship, 0, target, 0)
	if not aim.is_finite():
		aim = kin.relative(ship, target)
	if profile.aim_error > 0.0:
		var miss: Vector3 = Vector3(
			_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)
		)
		aim += miss * (profile.aim_error * aim.length())
	var c: AimMountCommand = AimMountCommand.new()
	c.aim_x = kin.px[ship] + aim.x
	c.aim_y = kin.py[ship] + aim.y
	c.aim_z = kin.pz[ship] + aim.z
	_submit(world, c)


## Lets go of the target: Face off, and stop if the crew has nothing else to fly to.
func _stand_down(world: SimWorld) -> void:
	if _target >= 0:
		_target = -1
		_helm(world, false, false)
		_submit(world, SelectTargetCommand.new())
		_moving = false
		_going = NONE


# --- Engineering ---


## Sends each idle repair crew to the most damaged subsystem no crew is working on.
func _repair(world: SimWorld) -> void:
	var def: ShipDef = world.defs[ship]
	var table: DamageTable = world.damage
	var busy: int = 0
	var worst: StringName = &""
	var worst_frac: float = 0.8
	for sub: SubsystemDef in def.subsystems:
		var row: int = table.find_subsystem(ship, sub.id)
		busy |= table.crews[row]
		var frac: float = table.health[row] / sub.health_max
		if frac < worst_frac and table.crews[row] == 0:
			worst = sub.id
			worst_frac = frac
	if worst == &"":
		return
	for crew: int in def.repair_crews:
		if busy & (1 << crew) == 0:
			var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
			dispatch.crew = crew
			dispatch.subsystem_id = worst
			_submit(world, dispatch)
			return


# --- fleeing and travelling ---


func _wants_flee(world: SimWorld) -> bool:
	if DamageSystem.hull_fraction(world, ship) >= profile.flee_hull:
		return false
	var enc: int = world.run.encounter[ship]
	return enc >= 0 and world.encounters.result[enc] == EncounterTable.Result.ACTIVE


func _flee(world: SimWorld) -> void:
	_target = -1
	_go(world, HOME, true)


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
	var enc: int = world.run.encounter[ship]
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
		var select: SelectTargetCommand = SelectTargetCommand.new()
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
	if world.kin.forward(ship).angle_to(offset) <= def.jump_face_tolerance_rad * JUMP_AIM:
		_jump_at = world.tick
		var jump: JumpCommand = JumpCommand.new()
		jump.target_kind = HelmTable.JumpKind.SITE
		jump.target_id = site
		_submit(world, jump)


# --- Comms ---


func _comms(world: SimWorld) -> void:
	var story: StoryTable = world.story
	for card: int in story.size():
		if not Story.visible_to(world, card, ship) or story.state[card] != StoryTable.State.OPEN:
			continue
		if story.kind[card] == StoryTable.Kind.HAIL:
			if profile.demands_surrender and story.conversation[card] == &"conv.surrender_demand":
				_demand_surrender(world, card)
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


# --- helpers ---


## Whether the situation `key` has stood for `seconds`; the clock starts the first time asked.
func _after(key: StringName, world: SimWorld, seconds: float) -> bool:
	if not _seen.has(key):
		_seen[key] = world.tick
	return world.tick - _seen[key] >= ceili(seconds * SimWorld.HZ)


func _after_card(world: SimWorld, card: int) -> bool:
	return _after(StringName("card%d" % card), world, profile.comms_s)


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
