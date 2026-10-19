class_name FlightFixture
extends RefCounted
## Helpers for the flight tests: a world with M1 corvettes at site 0, and Helm commands
## submitted the way a station sends them.

const DT: float = 1.0 / 60.0


static func world() -> SimWorld:
	return SimWorld.new(1, "test")


static func spawn(
	w: SimWorld,
	offset: Vector3 = Vector3.ZERO,
	rotation: Quaternion = Quaternion.IDENTITY,
	velocity: Vector3 = Vector3.ZERO,
	site: int = 0
) -> int:
	return w.spawn_ship(TestDefs.corvette(), 1, site, offset, rotation, velocity)


## Latches Helm input: rotation (pitch, yaw, roll), move (strafe, lift, throttle).
static func input(
	w: SimWorld,
	id: int,
	rotation: Vector3 = Vector3.ZERO,
	move: Vector3 = Vector3.ZERO,
	face: bool = false,
	approach: bool = false
) -> void:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.ship_id = id
	c.rotation = rotation
	c.strafe = move.x
	c.lift = move.y
	c.throttle = move.z
	c.face = face
	c.approach = approach
	w.submit(c)


static func select_ship(w: SimWorld, id: int, target: int) -> void:
	var c: SelectTargetCommand = SelectTargetCommand.new()
	c.ship_id = id
	c.target_ship = target
	w.submit(c)


static func select_point(w: SimWorld, id: int, site: int, p: Vector3) -> void:
	var c: SelectTargetCommand = SelectTargetCommand.new()
	c.ship_id = id
	c.site = site
	c.x = p.x
	c.y = p.y
	c.z = p.z
	w.submit(c)


static func decouple(w: SimWorld, id: int, on: bool) -> void:
	var c: DecoupledCommand = DecoupledCommand.new()
	c.ship_id = id
	c.decoupled = on
	w.submit(c)


static func all_stop(w: SimWorld, id: int) -> void:
	var c: AllStopCommand = AllStopCommand.new()
	c.ship_id = id
	w.submit(c)


static func level(w: SimWorld, id: int) -> void:
	var c: LevelCommand = LevelCommand.new()
	c.ship_id = id
	w.submit(c)


static func run(w: SimWorld, ticks: int) -> void:
	for i: int in ticks:
		w.step()


## Body-frame velocity of a ship (m/s).
static func local_velocity(w: SimWorld, id: int) -> Vector3:
	return w.kin.to_local(id, w.kin.vel[id])


## Angle (deg) between the bow and the direction to a site-frame offset.
static func bow_error_deg(w: SimWorld, id: int, offset: Vector3) -> float:
	return rad_to_deg(w.kin.forward(id).angle_to(offset))


## Propellant (kg) the integrator should charge for this tick's commands: impulse over
## exhaust velocity, torque counted as force over the lever arm (FT-SIM-007).
static func expected_propellant(w: SimWorld, id: int) -> float:
	var f: Vector3 = w.kin.clamp_thrust(id, w.kin.force_cmd[id])
	var tq: Vector3 = w.kin.clamp_torque(id, w.kin.torque_cmd[id])
	var effort: float = absf(f.x) + absf(f.y) + absf(f.z)
	effort += (absf(tq.x) + absf(tq.y) + absf(tq.z)) / w.kin.lever_arm[id]
	return effort * DT / w.kin.exhaust_velocity[id]
