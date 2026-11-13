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
## - A decoy (gp-13, launch_decoy) is a probe from stock that flies ShipDef.decoy_offset out
##   from the ship, square to the line to the nearest hostile, and for decoy_time draws
##   the hostile NPC AI within decoy_range of it (NpcAi engages decoy_near instead of its
##   target). It covers nothing and is dropped when its time is up (&"decoy_spent").
##
## Events: &"probe_launched", &"probe_deployed" (value = serial), &"probe_no_stock",
## &"probe_no_parts", &"probe_fabricating", &"probe_fabricated", &"lane_warning",
## &"decoy_launched" (value = serial), &"decoy_spent" (value = serial).


static func step(world: SimWorld) -> void:
	_fabricate(world)
	_fly(world)
	_burn_decoys(world)
	_warn_lanes(world)


## How close the point (m) is to the best deployed probe bubble of the faction: 1 at a probe,
## 0 on the edge of its bubble (minimum image distance over the launching ship's probe_range),
## negative outside; -INF when the faction has no deployed probe.
static func best_closeness(world: SimWorld, faction: int, at: PackedFloat64Array) -> float:
	var t: ProbeTable = world.probes
	var kin: Kinematics = world.kin
	var best: float = -INF
	for r: int in t.size():
		if t.owner_faction[r] != faction or not t.covers(r):
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


## Launches a decoy from the ship's stock (gp-13): it flies decoy_offset out, square to the
## line to the nearest hostile the faction has identified; false with no decoy on the
## ship, no such hostile, or (with &"probe_no_stock") no probe left.
static func launch_decoy(world: SimWorld, ship: int) -> bool:
	var def: ShipDef = world.defs[ship]
	var hostile: int = hostile_in_play(world, ship)
	if def.decoy_time <= 0.0 or hostile < 0:
		return false
	var r: RelayTable = world.relay
	if r.stock[ship] <= 0:
		world.emit(&"probe_no_stock", ship)
		return false
	var kin: Kinematics = world.kin
	var to_hostile: Vector3 = kin.relative(ship, hostile).normalized()
	var side: Vector3 = to_hostile.cross(kin.rot[ship] * Vector3.UP)
	if side.length_squared() < 1e-6:
		side = to_hostile.cross(kin.rot[ship] * Vector3.RIGHT)
	var to: PackedFloat64Array = kin.point_at(ship, side.normalized() * def.decoy_offset)
	r.stock[ship] -= 1
	var serial_no: int = r.launched[ship]
	r.launched[ship] += 1
	world.probes.launch(
		ship, world.faction_of(ship), serial_no, kin.point(ship), to, def.decoy_time
	)
	world.emit(&"decoy_launched", ship, hostile, serial_no)
	return true


## The nearest armed hostile NPC the ship's faction has identified (an H contact, never
## debris), or -1: what the decoy and the call for help need in play.
static func hostile_in_play(world: SimWorld, ship: int) -> int:
	return KnowledgeSystem.nearest_hostile(world, ship, INF, true, true)


## Whether the ship could launch a decoy now (what Relay's button shows on).
static func can_decoy(world: SimWorld, ship: int) -> bool:
	return (
		world.defs[ship].decoy_time > 0.0
		and world.relay.stock[ship] > 0
		and hostile_in_play(world, ship) >= 0
	)


## The live decoy nearest the AI ship of a faction hostile to it, within its launching
## ship's decoy_range, or -1 (a probe row).
static func decoy_near(world: SimWorld, id: int) -> int:
	var t: ProbeTable = world.probes
	var kin: Kinematics = world.kin
	var faction: int = world.faction_of(id)
	var best: int = -1
	var best_d: float = INF
	for r: int in t.size():
		if t.decoy_left[r] <= 0.0 or not world.is_hostile(faction, t.owner_faction[r]):
			continue
		var d: float = kin.relative_to_column(id, t.pos_x, t.pos_y, t.pos_z, r).length()
		if d <= world.defs[t.owner_ship[r]].decoy_range and d < best_d:
			best = r
			best_d = d
	return best


## A probe row's velocity (m/s): the launching ship's probe_speed toward its target
## while flying, zero once deployed.
static func velocity(world: SimWorld, r: int) -> Vector3:
	var t: ProbeTable = world.probes
	if t.deployed[r] == 1:
		return Vector3.ZERO
	var kin: Kinematics = world.kin
	var d: Vector3 = Vector3(
		kin.wrap(t.dest_x[r] - t.pos_x[r]),
		kin.wrap(t.dest_y[r] - t.pos_y[r]),
		kin.wrap(t.dest_z[r] - t.pos_z[r])
	)
	return d.normalized() * world.defs[t.owner_ship[r]].probe_speed


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
			if t.covers(r):
				world.emit(&"probe_deployed", t.owner_ship[r], -1, t.serial[r])
			continue
		var m: Vector3 = d.normalized() * stride
		t.pos_x[r] = kin.wrap(t.pos_x[r] + m.x)
		t.pos_y[r] = kin.wrap(t.pos_y[r] + m.y)
		t.pos_z[r] = kin.wrap(t.pos_z[r] + m.z)


## Counts the decoys down and drops the spent ones.
static func _burn_decoys(world: SimWorld) -> void:
	var t: ProbeTable = world.probes
	var spent: PackedInt32Array = PackedInt32Array()
	for r: int in t.size():
		if t.decoy_left[r] > 0.0:
			t.decoy_left[r] = maxf(0.0, t.decoy_left[r] - SimWorld.DT)
			if t.decoy_left[r] == 0.0:
				spent.append(r)
				world.emit(&"decoy_spent", t.owner_ship[r], -1, t.serial[r])
	t.remove_rows(spent)


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
