class_name ScriptedCrew
extends RefCounted
## A fixed crew script for the M1 encounter tests: before each step it submits the
## commands stations would send for the crewed ship. Tick 1 (once the sensors have run):
## select the enemy and hold Face. Every AIM_EVERY ticks: aim the bow mount at the
## enemy's lead intercept point. Every FIRE_EVERY ticks from FIRST_FIRE: fire. It reads
## the target's true state, as a crew with a radar lock would; it is deterministic, so
## the same world gives the same commands.

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
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.target_ship = target
		_submit(world, select)
		var helm: HelmInputCommand = HelmInputCommand.new()
		helm.face = true
		_submit(world, helm)
	if t >= 1 and t % AIM_EVERY == 0:
		_aim(world)
	if t >= FIRST_FIRE and t % FIRE_EVERY == 0:
		_submit(world, FireCommand.new())


func _aim(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var mount: MountDef = world.defs[ship].mounts[0]
	var muzzle: Vector3 = kin.to_world(ship, mount.position)
	var rel_vel: Vector3 = kin.vel[target] - kin.vel[ship]
	var rel: Vector3 = kin.relative(ship, target) - muzzle
	var lead_t: float = Lead.intercept_time(rel, rel_vel, mount.weapon.projectile_speed)
	var aim: Vector3 = muzzle + (Lead.aim_point(rel, rel_vel, lead_t) if lead_t >= 0.0 else rel)
	var c: AimMountCommand = AimMountCommand.new()
	c.aim_x = kin.px[ship] + aim.x
	c.aim_y = kin.py[ship] + aim.y
	c.aim_z = kin.pz[ship] + aim.z
	_submit(world, c)


func _submit(world: SimWorld, command: SimCommand) -> void:
	command.ship_id = ship
	world.submit(command)
