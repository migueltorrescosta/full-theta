# gdlint: disable=max-public-methods
class_name ApiCrew
extends RefCounted
## What a scripted crewman may do, as verbs (F10, FT-TST-022, D303): the seam the solo-lesson
## bots of director/ (TrainingCrew, TrainingPartners) act through, so they name no SimWorld.
## ScenarioApi.crew() hands it out. Each verb reads the true state, as a crew with a radar
## lock would, builds one or two real CREW commands of its own station and submits them, so
## the command log records them and a lesson replays. Every verb returns whether it sent
## anything. The station of a verb is fixed by the verb, which is how a bot can never send
## a command of another station. With `record` on, each command is also kept in `sent` as
## [tick, kind] (StationCatalogue.station_of_command(kind) gives its station).

## Whether verbs keep a record: [tick, kind] per command.
var record: bool = false
var sent: Array[Array] = []

var _world: SimWorld


func _init(world: SimWorld) -> void:
	_world = world


# --- reading ---


## Whether the ship exists and is alive.
func alive(ship: int) -> bool:
	return ship >= 0 and _world.kin.is_alive(ship)


## The nearest living hostile of the ship's faction that it detects within `reach` (any, or
## only armed ones), or -1.
func nearest_hostile(ship: int, reach: float, armed_only: bool = false) -> int:
	return KnowledgeSystem.nearest_hostile(_world, ship, reach, armed_only)


## Whether the ship's Science has no minigame open.
func science_idle(ship: int) -> bool:
	return _world.science.kind[ship] == ScienceTable.Minigame.NONE


# --- helm ---


## Helm holds station: releases a held face/approach, else All stop when the ship drifts
## faster than `rest_ms`.
func helm_settle(ship: int, rest_ms: float) -> bool:
	var held: bool = _world.helm.face_held[ship] == 1 or _world.helm.approach_held[ship] == 1
	if held:
		return _send(ship, HelmInputCommand.new())
	if _world.kin.vel[ship].length() > rest_ms and _world.helm.all_stop[ship] == 0:
		return _send(ship, AllStopCommand.new())
	return false


## The site of the ship's current encounter (pending or active), or -1.
func encounter_site(ship: int) -> int:
	var enc: int = _world.ships.encounter[ship]
	return _world.encounters.site[enc] if enc >= 0 else -1


## Whether the ship is at the site.
func at_site(ship: int, site: int) -> bool:
	return SiteTable.at_site(_world, ship) == site


## Selects the site and holds the ship facing it.
func face_site(ship: int, site: int) -> bool:
	var select: HelmSelectCommand = HelmSelectCommand.new()
	select.site_id = site
	_send(ship, select)
	var f: HelmInputCommand = HelmInputCommand.new()
	f.face = true
	return _send(ship, f)


## Jumps to the site once the drive is free and the bow is within `share` of the ship's jump
## tolerance; false (nothing sent) before then.
func jump_to(ship: int, site: int, share: float) -> bool:
	var offset: Vector3 = SiteTable.offset_to(_world, ship, site)
	if _world.helm.jump_left[ship] > 0 or not offset.is_finite():
		return false
	if _world.kin.forward(ship).angle_to(offset) > _world.defs[ship].jump_face_tolerance * share:
		return false
	var jump: JumpCommand = JumpCommand.new()
	jump.target_kind = HelmTable.JumpKind.SITE
	jump.target_id = site
	return _send(ship, jump)


func helm_speed(ship: int, throttle: float) -> bool:
	var h: HelmInputCommand = HelmInputCommand.new()
	h.throttle = throttle
	return _send(ship, h)


## Selects `target` (when 0 or more) and holds the ship facing it, or approaching it, at
## `throttle` (0 holds the speed).
func helm_face(ship: int, target: int, approach: bool, throttle: float = 0.0) -> bool:
	if target >= 0:
		var select: HelmSelectCommand = HelmSelectCommand.new()
		select.contact = target
		_send(ship, select)
	var f: HelmInputCommand = HelmInputCommand.new()
	f.face = true
	f.approach = approach
	f.throttle = throttle
	return _send(ship, f)


## The ship's speed (m/s).
func speed(ship: int) -> float:
	return _world.kin.vel[ship].length()


# --- weapons ---


## Aims the mount (0, the bow, by default) at the target's lead point, off by `error` rad in
## a direction drawn from `rng` (a stand-in's loose aim, StandInCrew); 0 is a perfect lead.
func aim_at(
	ship: int, target: int, error: float = 0.0, rng: RandomNumberGenerator = null, mount: int = 0
) -> bool:
	return _send(ship, CrewMoves.aim(_world, ship, target, error, rng, mount))


## The first mount whose arc holds the target, else 0 (CrewMoves.mount_for, gp-12).
func mount_for(ship: int, target: int) -> int:
	return CrewMoves.mount_for(_world, ship, target)


## Asks the mount (0 by default) for one shot (WeaponSystem fires it or says why not).
func fire(ship: int, mount: int = 0) -> bool:
	var c: FireCommand = FireCommand.new()
	c.mount_index = mount
	return _send(ship, c)


## The distance from the ship to another (m).
func range_to(ship: int, other: int) -> float:
	return _world.kin.relative(ship, other).length()


# --- engineering ---


## Sends the first idle repair crew to the most damaged subsystem no crew works on.
func repair_next(ship: int) -> bool:
	var repair: DispatchRepairCommand = CrewMoves.repair(_world, ship)
	return repair != null and _send(ship, repair)


## Brings the first subsystem (not the reactor) that runs above `share` of its fault heat and
## above its nominal pips back to the nominal pips.
func cool_hot(ship: int, share: float) -> bool:
	var def: ShipDef = _world.defs[ship]
	for i: int in def.subsystems.size():
		var sub: SubsystemDef = def.subsystems[i]
		var row: int = _world.damage.subsystem_row(ship, i)
		var hot: bool = _world.damage.heat[row] > share * sub.fault_heat_threshold
		if (
			sub.kind != SubsystemDef.Kind.REACTOR
			and hot
			and _world.damage.pips[row] > sub.nominal_pips
		):
			var cool: SetPipsCommand = SetPipsCommand.new()
			cool.subsystem_kind = sub.kind
			cool.pips = sub.nominal_pips
			return _send(ship, cool)
	return false


func boost(ship: int) -> bool:
	return _send(ship, BoostCommand.new())


## One more pip on a subsystem (one fewer when it is at the top), taking it from the engines
## when the reactor has none to spare.
func pip_up(ship: int, kind: int) -> bool:
	var def: ShipDef = _world.defs[ship]
	var cur: int = 0
	var used: int = 0
	var engines: int = 0
	for i: int in def.subsystems.size():
		var sub: SubsystemDef = def.subsystems[i]
		var pips: int = _world.damage.pips[_world.damage.subsystem_row(ship, i)]
		used += pips
		if sub.kind == kind:
			cur = pips
		if sub.kind == SubsystemDef.Kind.ENGINES:
			engines = pips
	var want: SetPipsCommand = SetPipsCommand.new()
	want.subsystem_kind = kind
	if cur >= def.power.max_pips_per_subsystem:
		want.pips = cur - 1
	else:
		want.pips = cur + 1
		if used + 1 > PowerSystem.pip_cap(_world, ship):
			var give: SetPipsCommand = SetPipsCommand.new()
			give.subsystem_kind = SubsystemDef.Kind.ENGINES
			give.pips = maxi(0, engines - 1)
			_send(ship, give)
	return _send(ship, want)


# --- science ---


func scan(ship: int, target: int) -> bool:
	var scan_cmd: ScienceScanCommand = ScienceScanCommand.new()
	scan_cmd.contact = target
	return _send(ship, scan_cmd)


## Closes the open scan, then opens a new one on `target`.
func rescan(ship: int, target: int) -> bool:
	_send(ship, ScienceCancelCommand.new())
	return scan(ship, target)


func cancel_scan(ship: int) -> bool:
	return _send(ship, ScienceCancelCommand.new())


# --- relay ---


## Launches a probe `distance` metres ahead of the ship.
func launch_probe(ship: int, distance: float) -> bool:
	var at: PackedFloat64Array = _world.kin.point_at(ship, _world.kin.forward(ship) * distance)
	var probe: LaunchProbeCommand = LaunchProbeCommand.new()
	probe.x = at[0]
	probe.y = at[1]
	probe.z = at[2]
	return _send(ship, probe)


# --- comms ---


## Answers the first open hail the ship can see.
func answer_hail(ship: int) -> bool:
	var story: StoryTable = _world.story
	for card: int in story.size():
		if not Story.visible_to(_world, card, ship):
			continue
		if story.kind[card] == StoryTable.Kind.HAIL and story.state[card] == StoryTable.State.OPEN:
			var answer: AnswerHailCommand = AnswerHailCommand.new()
			answer.card = card
			return _send(ship, answer)
	return false


# --- training ---


## Presses Next for `station` in a pair step (not kept in `sent`).
func press_next(ship: int, station: StringName) -> void:
	var press: TrainingNextCommand = TrainingNextCommand.new()
	press.ship_id = ship
	press.station = station
	_world.submit(press)


func _send(ship: int, command: SimCommand) -> bool:
	command.ship_id = ship
	_world.submit(command)
	if record:
		sent.append([_world.tick, command.kind()])
	return true
