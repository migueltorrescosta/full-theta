extends GdUnitTestSuite
## Every path that takes a point keeps it 64-bit (D104, D401): a point float32 cannot hold,
## 1 km inside the seam with a sub-millimetre fraction, lands in the stored float64 columns
## exactly, and the column form of the minimum-image delta matches the point form.

## Probe bubble for the coverage case (m).
const PROBE_RANGE: float = 1000.0


## The points fed through every path: each axis at +/-(P/2 - 1000.123) m.
static func points(period: float) -> Array[PackedFloat64Array]:
	var a: float = 0.5 * period - 1000.123
	return [CubePoint.make(a, a, a), CubePoint.make(-a, a, -a), CubePoint.make(-a, -a, -a)]


func world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1)
	return w


func fleet_world() -> SimWorld:
	return FleetFixture.make(GameRules.Mode.HOLDOUT, 3).world


## [name, Callable() -> the world, Callable(world, point) -> the points it stored].
func cases() -> Array:
	return [
		["spawn_ship", world, _spawn_ship],
		["spawn_npc", world, _spawn_npc],
		["reset_ship", world, _reset_ship],
		["SpawnShipCommand", world, _spawn_command],
		["RunSetup ship_starts", fleet_world, _ship_start],
		["ProbeTable.launch", world, _probe_launch],
		["ProbeSystem.coverage_at", world, _probe_coverage],
		["ProjectileTable.spawn", world, _projectile],
	]


func _spawn_ship(w: SimWorld, p: PackedFloat64Array) -> Array:
	return [w.kin.point(w.spawn_ship(TestDefs.corvette(), 1, p))]


func _spawn_npc(w: SimWorld, p: PackedFloat64Array) -> Array:
	return [w.kin.point(w.spawn_npc(TestDefs.raider_enemy(), 2, p))]


func _reset_ship(w: SimWorld, p: PackedFloat64Array) -> Array:
	w.reset_ship(0, p)
	return [w.kin.point(0)]


func _spawn_command(w: SimWorld, p: PackedFloat64Array) -> Array:
	w.catalog[&"raider"] = TestDefs.raider_enemy()
	var c: SpawnShipCommand = SpawnShipCommand.new()
	c.npc_key = &"raider"
	c.faction = 2
	c.x = p[0]
	c.y = p[1]
	c.z = p[2]
	assert_bool(c.apply(w)).is_true()
	return [w.kin.point(c.result_id)]


# The build stores each start as placed; a relaunch puts the ship back at its start.
func _ship_start(w: SimWorld, p: PackedFloat64Array) -> Array:
	assert_array(Array(w.kin.point(0))).is_equal(Array(w.ship_starts[0]))
	w.ship_starts[0] = p
	w.ships.status[0] = ShipStateTable.Status.DESTROYED
	var c: RelaunchShipCommand = RelaunchShipCommand.new()
	c.ship = 0
	assert_bool(c.apply(w)).is_true()
	return [w.ship_starts[0], w.kin.point(0)]


func _probe_launch(w: SimWorld, p: PackedFloat64Array) -> Array:
	w.kin.place(0, p)
	w.relay.stock[0] = 1
	assert_bool(ProbeSystem.launch(w, 0, p)).is_true()
	var t: ProbeTable = w.probes
	return [
		CubePoint.read(t.pos_x, t.pos_y, t.pos_z, 0),
		CubePoint.read(t.dest_x, t.dest_y, t.dest_z, 0),
	]


# 1 mm either side of the bubble's edge: float32 near the seam would round to 16 mm.
func _probe_coverage(w: SimWorld, p: PackedFloat64Array) -> Array:
	var def: ShipDef = w.defs[0].duplicate()
	def.probe_range = PROBE_RANGE
	w.defs[0] = def
	var f: int = w.faction_of(0)
	w.probes.launch(0, f, 0, p, p)
	w.probes.deployed[0] = 1
	var inside: PackedFloat64Array = CubePoint.make(p[0] + PROBE_RANGE - 0.001, p[1], p[2])
	var outside: PackedFloat64Array = CubePoint.make(p[0] + PROBE_RANGE + 0.001, p[1], p[2])
	assert_bool(ProbeSystem.coverage_at(w, f, inside)).is_true()
	assert_bool(ProbeSystem.coverage_at(w, f, outside)).is_false()
	var t: ProbeTable = w.probes
	return [CubePoint.read(t.pos_x, t.pos_y, t.pos_z, 0)]


func _projectile(w: SimWorld, p: PackedFloat64Array) -> Array:
	var t: ProjectileTable = w.projectiles
	var k: int = t.spawn(0, 1, p, Vector3.ZERO, 1.0, 1.0, 10)
	return [CubePoint.read(t.pos_x, t.pos_y, t.pos_z, k)]


# FT: FT-SIM-035
# Each path stores the point's three float64 coordinates exactly (D104, D401).
func test_every_path_keeps_the_point_64_bit() -> void:
	for c: Array in cases():
		var make: Callable = c[1]
		var probe: SimWorld = make.call()
		for p: PackedFloat64Array in points(probe.kin.period):
			assert_float(Vector3(p[0], p[1], p[2]).x).is_not_equal(p[0])
			var w: SimWorld = make.call()
			var stored: Array = (c[2] as Callable).call(w, p)
			for s: PackedFloat64Array in stored:
				(
					assert_array(Array(s))
					. override_failure_message("%s lost precision: %s" % [c[0], s])
					. is_equal(Array(p))
				)


# FT: FT-SIM-035
# delta_column gives the same minimum-image vector as delta for pairs straddling +/-P/2
# with sub-centimetre fractions (D401).
func test_delta_column_matches_delta_across_the_seam() -> void:
	var w: SimWorld = world()
	var half: float = 0.5 * w.kin.period
	var xs: PackedFloat64Array = PackedFloat64Array()
	var ys: PackedFloat64Array = PackedFloat64Array()
	var zs: PackedFloat64Array = PackedFloat64Array()
	var bs: Array[PackedFloat64Array] = []
	for f: float in [0.0013, 0.0071, 0.0049]:
		CubePoint.append(xs, ys, zs, CubePoint.make(half - f, -half + f, half - 3.0 - f))
		bs.append(CubePoint.make(-half + 2.0 * f, half - 5.0 * f, -half + 1.0 + f))
		CubePoint.append(xs, ys, zs, CubePoint.make(-half + f, half - 0.5 * f, 0.25 + f))
		bs.append(CubePoint.make(half - 0.75 * f, -half + f, -0.25 - f))
	for r: int in xs.size():
		var a: PackedFloat64Array = CubePoint.read(xs, ys, zs, r)
		var d: Vector3 = w.kin.delta_column(xs, ys, zs, r, bs[r])
		assert_vector(d).is_equal(w.kin.delta(a, bs[r]))
		assert_float(d.length()).is_less(10.0)
