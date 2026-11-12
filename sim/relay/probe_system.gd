class_name ProbeSystem
extends RefCounted
## Relay's probes, Engineering's probe fabrication and the firing-lane warning (E02, D56,
## P8, P11, P13; FT-RLY-004, FT-RLY-011). Runs once per tick, before the integrator.
##
## - A launched probe flies straight to its target along the minimum image at the
##   launching ship's probe_speed and deploys there (&"probe_deployed").
## - A deployed probe covers a bubble of probe_range around itself for its faction
##   (coverage_at): Science's noise model reads it, so a contact inside a bubble is
##   scanned as if in own range (P13).
## - Fabrication takes ShipDef.probe_parts spare parts when it starts and adds a probe
##   to the stock after probe_fab_time (&"probe_fabricated").
## - With lane flagging on (FlagLanesCommand) a mount whose next shot would cross a
##   friendly or neutral ship raises &"lane_warning" once per crossing, before the shot
##   (other_id = that ship, value = mount index); firing still works (FT-SIM-016).
##
## Events: &"probe_launched", &"probe_deployed" (value = serial), &"probe_no_stock",
## &"probe_no_parts", &"probe_fabricating", &"probe_fabricated", &"lane_warning".


static func step(world: SimWorld) -> void:
	_fabricate(world)
	_fly(world)
	_warn_lanes(world)


## How close the point (m) is to the best deployed probe bubble of the faction: 1 at a probe,
## 0 on the edge of its bubble (minimum image distance over the launching ship's probe_range),
## negative outside; -INF when the faction has no deployed probe.
static func best_closeness(world: SimWorld, faction: int, at: PackedFloat64Array) -> float:
	var t: ProbeTable = world.probes
	var kin: Kinematics = world.kin
	var best: float = -INF
	for r: int in t.size():
		if t.owner_faction[r] != faction or t.deployed[r] == 0:
			continue
		var d: Vector3 = kin.delta_column(t.pos_x, t.pos_y, t.pos_z, r, at)
		best = maxf(best, 1.0 - d.length() / world.defs[t.owner_ship[r]].probe_range)
	return best


## Whether a deployed probe of the faction covers the point (m): the minimum
## image distance to its position is within the launching ship's probe_range.
static func coverage_at(world: SimWorld, faction: int, at: PackedFloat64Array) -> bool:
	return best_closeness(world, faction, at) >= 0.0


## Whether a deployed probe of the ship's faction covers the contact (P13).
static func covers_contact(world: SimWorld, ship: int, contact: int) -> bool:
	return coverage_at(world, world.faction_of(ship), world.kin.point(contact))


## Launches one probe toward a point (m) from the ship's stock; false (with
## &"probe_no_stock") when none is left or the point is not finite.
static func launch(world: SimWorld, ship: int, at: PackedFloat64Array) -> bool:
	var r: RelayTable = world.relay
	var kin: Kinematics = world.kin
	var to: PackedFloat64Array = kin.wrap_point(at)
	if to.is_empty():
		return false
	if r.stock[ship] <= 0:
		world.emit(&"probe_no_stock", ship)
		return false
	r.stock[ship] -= 1
	var serial_no: int = r.launched[ship]
	r.launched[ship] += 1
	world.probes.launch(ship, world.faction_of(ship), serial_no, kin.point(ship), to)
	world.emit(&"probe_launched", ship, -1, serial_no)
	return true


## Starts Engineering's probe fabrication from spare parts (P11); false with a reason
## event when it can't.
static func fabricate(world: SimWorld, ship: int) -> bool:
	var def: ShipDef = world.defs[ship]
	var r: RelayTable = world.relay
	var hull: int = world.damage.hull_row(ship)
	if def.probe_parts <= 0 or r.fab_left[ship] > 0.0:
		return false
	if world.damage.spare_parts[hull] < def.probe_parts:
		world.emit(&"probe_no_parts", ship)
		return false
	world.damage.spare_parts[hull] -= def.probe_parts
	r.fab_left[ship] = def.probe_fab_time
	world.emit(&"probe_fabricating", ship, -1, def.probe_fab_time)
	return true


static func _fabricate(world: SimWorld) -> void:
	var r: RelayTable = world.relay
	for ship: int in r.size():
		if r.fab_left[ship] <= 0.0:
			continue
		r.fab_left[ship] = maxf(0.0, r.fab_left[ship] - SimWorld.DT)
		if r.fab_left[ship] == 0.0:
			r.stock[ship] += 1
			world.emit(&"probe_fabricated", ship)


static func _fly(world: SimWorld) -> void:
	var t: ProbeTable = world.probes
	var kin: Kinematics = world.kin
	for r: int in t.size():
		if t.deployed[r] == 1:
			continue
		var speed: float = world.defs[t.owner_ship[r]].probe_speed
		var d: Vector3 = Vector3(
			kin.wrap(t.dest_x[r] - t.pos_x[r]),
			kin.wrap(t.dest_y[r] - t.pos_y[r]),
			kin.wrap(t.dest_z[r] - t.pos_z[r])
		)
		var stride: float = speed * SimWorld.DT
		if d.length() <= stride:
			t.pos_x[r] = t.dest_x[r]
			t.pos_y[r] = t.dest_y[r]
			t.pos_z[r] = t.dest_z[r]
			t.deployed[r] = 1
			world.emit(&"probe_deployed", t.owner_ship[r], -1, t.serial[r])
			continue
		var m: Vector3 = d.normalized() * stride
		t.pos_x[r] = kin.wrap(t.pos_x[r] + m.x)
		t.pos_y[r] = kin.wrap(t.pos_y[r] + m.y)
		t.pos_z[r] = kin.wrap(t.pos_z[r] + m.z)


static func _warn_lanes(world: SimWorld) -> void:
	var rt: RelayTable = world.relay
	var mounts: MountTable = world.mounts
	for ship: int in rt.size():
		if rt.lanes_flagged[ship] == 0 or not world.kin.is_alive(ship):
			continue
		var friend: int = -1
		var index: int = 0
		for row: int in mounts.rows_of(ship):
			friend = WeaponSystem.path_crosses(world, row)
			if friend >= 0:
				index = mounts.mount_index[row]
				break
		if friend != rt.lane_warned[ship]:
			rt.lane_warned[ship] = friend
			if friend >= 0:
				world.emit(&"lane_warning", ship, friend, index)
