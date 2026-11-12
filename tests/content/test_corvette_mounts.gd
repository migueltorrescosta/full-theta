extends GdUnitTestSuite
## gp-12: the run's corvette (content/ships/m1_corvette.tres) carries three mounts, bow,
## port and starboard, each a claim item of its own; each fires inside its own arc only,
## and the side arcs overlap the bow arc a little.

const FAR: float = 2000.0


# FT: FT-WPN-010, FT-NET-022
func test_corvette_has_three_claimable_mounts() -> void:
	var def: ShipDef = TestDefs.corvette()
	var ids: Array = def.mounts.map(func(m: MountDef) -> StringName: return m.id)
	assert_array(ids).is_equal([&"bow", &"port", &"starboard"])
	for m: MountDef in def.mounts:
		assert_array(m.validate()).is_empty()
	var w: SimWorld = SimWorld.new(1)
	w.spawn_ship(def, 1)
	var items: Array = StationBlocks.claim_items(w, 0)["weapons"]
	assert_array(items).is_equal(["mount:0", "mount:1", "mount:2"])
	# The side arcs reach a little past the bow arc's edge.
	var bow: MountDef = def.mounts[0]
	for side: MountDef in [def.mounts[1], def.mounts[2]]:
		var gap: float = side.forward.angle_to(bow.forward)
		assert_float(gap - side.arc_half_angle).is_less(bow.arc_half_angle)
		assert_float(gap - side.arc_half_angle).is_greater(0.0)


# FT: FT-WPN-010, FT-SIM-011
# Each mount fires at a point along its own forward and is blocked by its arc astern.
func test_each_mount_fires_in_its_arc() -> void:
	var def: ShipDef = TestDefs.corvette()
	for m: int in def.mounts.size():
		var mount: MountDef = def.mounts[m]
		for case: Array in [[mount.forward, "fired"], [Vector3.BACK, "arc"]]:
			var w: SimWorld = SimWorld.new(1)
			w.spawn_ship(def, 1)
			var aim: AimMountCommand = AimMountCommand.new()
			aim.ship_id = 0
			aim.mount_index = m
			var p: Vector3 = mount.position + (case[0] as Vector3) * FAR
			aim.aim_x = p.x
			aim.aim_y = p.y
			aim.aim_z = p.z
			w.submit(aim)
			var fire: FireCommand = FireCommand.new()
			fire.ship_id = 0
			fire.mount_index = m
			w.submit(fire)
			var events: Array[SimEvent] = SimFixture.run(w, 1)
			var fired: Array[SimEvent] = SimFixture.of_kind(events, &"fired")
			var blocked: Array[SimEvent] = SimFixture.of_kind(events, &"fire_blocked")
			var got: String = "fired" if not fired.is_empty() else String(blocked[0].tag)
			assert_str(got).override_failure_message("%s %s" % [mount.id, case[1]]).is_equal(
				case[1]
			)
			if not fired.is_empty():
				assert_int(int(fired[0].value)).is_equal(m)
