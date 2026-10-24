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
##   to the stock after probe_fab_s (&"probe_fabricated").
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


## Whether a deployed probe of the faction covers the site-local point (m): the minimum
## image distance to its position is within the launching ship's probe_range.
static func coverage_at(world: SimWorld, faction: int, pos: Vector3, site: int = 0) -> bool:
	var t: ProbeTable = world.probes
	var kin: Kinematics = world.kin
	for r: int in t.size():
		if t.factions[r] != faction or t.deployed[r] == 0 or t.site[r] != site:
			continue
		var d: Vector3 = Vector3(
			kin.wrap(pos.x - t.at_x[r]), kin.wrap(pos.y - t.at_y[r]), kin.wrap(pos.z - t.at_z[r])
		)
		if d.length() <= world.defs[t.ship_ids[r]].probe_range:
			return true
	return false


## Whether a deployed probe of the ship's faction covers the contact (P13): the wiring
## ScienceSystem.probe_covered falls back to when SimWorld.probe_coverage is not set.
static func covers_contact(world: SimWorld, ship: int, contact: int) -> bool:
	var kin: Kinematics = world.kin
	var p: PackedFloat64Array = kin.point_at(contact, Vector3.ZERO)
	return coverage_at(world, world.faction_of(ship), Vector3(p[0], p[1], p[2]), kin.site[contact])


## Launches one probe toward a site-local point (m) from the ship's stock; false (with
## &"probe_no_stock") when none is left or the point is not finite.
static func launch(world: SimWorld, ship: int, x: float, y: float, z: float) -> bool:
	var r: RelayTable = world.relay
	var kin: Kinematics = world.kin
	var to: PackedFloat64Array = kin.wrap_point(x, y, z)
	if to.is_empty():
		return false
	if r.stock[ship] <= 0:
		world.emit(&"probe_no_stock", ship)
		return false
	r.stock[ship] -= 1
	var serial_no: int = r.launched[ship]
	r.launched[ship] += 1
	var from: PackedFloat64Array = kin.point_at(ship, Vector3.ZERO)
	world.probes.launch(
		ship,
		world.faction_of(ship),
		serial_no,
		kin.site[ship],
		Vector3(from[0], from[1], from[2]),
		Vector3(to[0], to[1], to[2])
	)
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
	r.fab_left[ship] = def.probe_fab_s
	world.emit(&"probe_fabricating", ship, -1, def.probe_fab_s)
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
		var speed: float = world.defs[t.ship_ids[r]].probe_speed
		var d: Vector3 = Vector3(
			kin.wrap(t.to_x[r] - t.at_x[r]),
			kin.wrap(t.to_y[r] - t.at_y[r]),
			kin.wrap(t.to_z[r] - t.at_z[r])
		)
		var step_m: float = speed * SimWorld.DT
		if d.length() <= step_m:
			t.at_x[r] = t.to_x[r]
			t.at_y[r] = t.to_y[r]
			t.at_z[r] = t.to_z[r]
			t.deployed[r] = 1
			world.emit(&"probe_deployed", t.ship_ids[r], -1, t.serial[r])
			continue
		var m: Vector3 = d.normalized() * step_m
		t.at_x[r] = kin.wrap(t.at_x[r] + m.x)
		t.at_y[r] = kin.wrap(t.at_y[r] + m.y)
		t.at_z[r] = kin.wrap(t.at_z[r] + m.z)


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
