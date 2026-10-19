class_name S6Intercept
extends RefCounted
## R16 check (FT-SIM-035, D98): a scripted intercept run in S6WorldPacked.
## Ship 0 shoots one projectile with lead at ship 1, which thrusts and
## tumbles; ship 2 flies the same inputs as ship 1 and closes on it to
## contact. `base` is added to every starting position: Vector3.ZERO for
## site-local runs (only the site id changes), the site's global position
## for the naive global float32 run.

const TICKS: int = 600
const SHOOTER: int = 0
const TARGET: int = 1
const CHASER: int = 2


static func run(site: int, base: Vector3) -> Dictionary:
	var w := S6WorldPacked.new(1)
	var tumble := Quaternion(Vector3(0.3, 1.0, -0.2).normalized(), 0.7)
	var thrust := Vector3(0.0, 0.0, -1.0e5)
	var torque := Vector3(2.0e4, 0.0, 1.0e4)
	var target_vel := Vector3(-40.0, 15.0, 5.0)
	var target_pos := Vector3(3000.0, 400.0, -200.0)
	w.add_ship(
		site, base, Vector3(12.0, -3.0, 0.5), Quaternion.IDENTITY, Vector3.ZERO, Vector3.ZERO
	)
	w.add_ship(site, base + target_pos, target_vel, tumble, thrust, torque)
	w.add_ship(
		site,
		base + target_pos + Vector3(600.0, 0.0, 0.0),
		target_vel + Vector3(-60.0, 0.0, 0.0),
		tumble,
		thrust,
		torque
	)
	# First-order lead from the positions the sim holds, as a gunner sees them.
	var sp := w.ship_pos(SHOOTER)
	var sv := w.ship_vel(SHOOTER)
	var rel := w.ship_pos(TARGET) - sp
	var lead: float = rel.length() / S6WorldPacked.PROJ_SPEED
	var dir := (rel + (w.ship_vel(TARGET) - sv) * lead).normalized()
	w.add_projectile(
		site, sp + dir * (S6WorldPacked.SHIP_RADIUS + 2.0), sv + dir * S6WorldPacked.PROJ_SPEED, 300
	)
	var out := {"hit_tick": -1, "hit_ship": -1, "warn_tick": -1, "contact_tick": -1}
	for i in TICKS:
		w.step()
		var ev := w.events
		for e in range(0, ev.size(), 4):
			match ev[e + 1]:
				S6WorldPacked.EV_HIT:
					if out["hit_tick"] < 0:
						out["hit_tick"] = ev[e]
						out["hit_ship"] = ev[e + 3]
				S6WorldPacked.EV_PROXIMITY:
					if out["warn_tick"] < 0 and ev[e + 2] == TARGET:
						out["warn_tick"] = ev[e]
				S6WorldPacked.EV_CONTACT:
					if out["contact_tick"] < 0 and ev[e + 2] == TARGET:
						out["contact_tick"] = ev[e]
	var ships: Array[Vector3] = []
	var rots: Array[Quaternion] = []
	for s in w.ship_count():
		ships.append(w.ship_pos(s))
		rots.append(w.ship_rot(s))
	out["pos"] = ships
	out["rot"] = rots
	out["proj"] = w.proj_pos(0)
	return out


## Global position in float64 (GDScript float) from a site origin and a
## float32 offset: what the Relay map or a jump would use.
static func world_position(origin: PackedFloat64Array, offset: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([origin[0] + offset.x, origin[1] + offset.y, origin[2] + offset.z])


## Largest per-ship position error, in metres, of `run` against `ref`,
## after removing `base` in float64.
static func max_error(run_out: Dictionary, ref: Dictionary, base: Vector3) -> float:
	var worst: float = 0.0
	var a: Array[Vector3] = run_out["pos"]
	var b: Array[Vector3] = ref["pos"]
	for s in a.size():
		var dx: float = (float(a[s].x) - float(base.x)) - b[s].x
		var dy: float = (float(a[s].y) - float(base.y)) - b[s].y
		var dz: float = (float(a[s].z) - float(base.z)) - b[s].z
		worst = maxf(worst, sqrt(dx * dx + dy * dy + dz * dz))
	return worst
