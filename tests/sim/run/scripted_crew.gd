class_name ScriptedCrew
extends RefCounted
## A fixed crew script for the M1 encounter tests: before each step it submits the
## commands stations would send for the crewed ship. Tick 1 (once the sensors have run):
## put the reactor's 2 spare pips on the weapons (a shot costs more than two pips recharge
## at the cooldown rate, D212), select the enemy and hold Face. Every AIM_EVERY ticks: aim
## the bow mount at the enemy's lead intercept point. Every FIRE_EVERY ticks from
## FIRST_FIRE: fire. It reads the target's true state, as a crew with a radar lock would; it
## is deterministic, so the same world gives the same commands.

const AIM_EVERY: int = 6
const FIRE_EVERY: int = 30
const FIRST_FIRE: int = 60

var ship: int
var target: int


func _init(ship_id: int = M1Encounter.PLAYER_SHIP, target_id: int = M1Encounter.ENEMY_SHIP) -> void:
	ship = ship_id
	target = target_id


## Submits this tick's commands; call it right before world.step().
func act(world: SimWorld) -> void:
	var t: int = world.tick
	if not world.kin.is_alive(ship) or not world.kin.is_alive(target):
		return
	if t == 1:
		var pips: SetPipsCommand = SetPipsCommand.new()
		pips.subsystem_kind = SubsystemDef.Kind.WEAPONS
		pips.pips = world.defs[ship].power.max_pips_per_subsystem
		_submit(world, pips)
		var select: HelmSelectCommand = HelmSelectCommand.new()
		select.contact = target
		_submit(world, select)
		var helm: HelmInputCommand = HelmInputCommand.new()
		helm.face = true
		_submit(world, helm)
	if t >= 1 and t % AIM_EVERY == 0:
		_aim(world)
		_repair_weapons(world)
	if t >= FIRST_FIRE and t % FIRE_EVERY == 0:
		_submit(world, FireCommand.new())


## Sends every idle crew to the weapons while they are damaged: a damaged weapons
## subsystem recharges the store slower (R16-3), so a crew that does not repair loses the fight.
func _repair_weapons(world: SimWorld) -> void:
	var def: ShipDef = world.defs[ship]
	var index: int = PowerSystem.subsystem_index(def, SubsystemDef.Kind.WEAPONS)
	var row: int = world.damage.subsystem_row(ship, index)
	if world.damage.health[row] >= def.subsystems[index].health_max:
		return
	for crew: int in def.repair_crews:
		if world.damage.crews[row] & (1 << crew) != 0:
			continue
		var c: DispatchRepairCommand = DispatchRepairCommand.new()
		c.crew = crew
		c.subsystem_id = def.subsystems[index].id
		_submit(world, c)


func _aim(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var aim: Vector3 = EnemyAi.lead_aim(world, ship, 0, target, 0)
	if not aim.is_finite():
		aim = kin.relative(ship, target)
	var c: AimMountCommand = AimMountCommand.new()
	c.aim_x = kin.pos_x[ship] + aim.x
	c.aim_y = kin.pos_y[ship] + aim.y
	c.aim_z = kin.pos_z[ship] + aim.z
	_submit(world, c)


func _submit(world: SimWorld, command: SimCommand) -> void:
	command.ship_id = ship
	world.submit(command)
