extends GdUnitTestSuite
## T031: shields with one focus direction (Helm), power and tightness (Engineering),
## absorption by power, tightness and hit angle, the 40 % alert and no frequencies (L2).
## M1 corvette shields: 3e7 J, regen 5e5 J/s at nominal power, tightness 0 to 4,
## absorption 1, alert at 0.4; 2 nominal shield pips of 12.

const SHD: int = SubsystemDef.Kind.SHIELDS


func _world(n: int = 1) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	for i: int in n:
		w.spawn_ship(TestDefs.corvette(), 1, 0, Vector3(0, 0, -1000.0 * i))
	return w


func _shield(w: SimWorld, power: int, tightness: float) -> bool:
	var c: SetShieldCommand = SetShieldCommand.new()
	c.ship_id = 0
	c.power = power
	c.tightness = tightness
	w.submit(c)
	var logged: int = w.command_log.size()
	w.step()
	return w.command_log.size() > logged


func _focus(w: SimWorld, direction: Vector3, track: int = -1) -> bool:
	var c: SetShieldFocusCommand = SetShieldFocusCommand.new()
	c.ship_id = 0
	c.direction = direction
	c.track_id = track
	w.submit(c)
	var logged: int = w.command_log.size()
	w.step()
	return w.command_log.size() > logged


## Energy that passes a 1 MJ hit from a ship-frame direction, through the hit resolver.
func _through(w: SimWorld, from_local: Vector3, energy: float = 1e6) -> float:
	var hit: SimHit = SimHit.new()
	hit.target_id = 0
	hit.kind = &"projectile"
	hit.from_local = from_local
	hit.energy = energy
	w.hits.append(hit)
	w.drain_events()
	w.step()
	for e: SimEvent in w.drain_events():
		if e.kind == &"hit":
			return e.value
	return -1.0


# FT: FT-SIM-019
# Absorbed share against shield pips, tightness and the angle between focus and hit:
# 1 - exp(-pips/2 * coverage), coverage = 2k e^(k (cos - 1)) / (1 - e^-2k). Expected
# values computed independently to 6 decimals.
func test_absorption_table() -> void:
	# [pips, tightness, [absorbed at 0, 90, 180 degrees from the focus]]
	var table: Array[Array] = [
		[0, 0.0, [0.0, 0.0, 0.0]],
		[0, 4.0, [0.0, 0.0, 0.0]],
		[1, 0.0, [0.393469, 0.393469, 0.393469]],
		[1, 2.0, [0.869622, 0.240975, 0.036627]],
		[1, 4.0, [0.981709, 0.070666, 0.001341]],
		[2, 0.0, [0.632121, 0.632121, 0.632121]],
		[2, 2.0, [0.983001, 0.423881, 0.071913]],
		[2, 4.0, [0.999665, 0.136338, 0.002681]],
		[4, 0.0, [0.864665, 0.864665, 0.864665]],
		[4, 2.0, [0.999711, 0.668087, 0.138654]],
		[4, 4.0, [1.0, 0.254089, 0.005355]],
	]
	var dirs: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK]
	for row: Array in table:
		var w: SimWorld = _world()
		assert_bool(_shield(w, row[0], row[1])).is_true()
		for i: int in 3:
			var got: float = ShieldSystem.absorb_fraction(w, 0, dirs[i])
			(
				assert_float(got)
				. override_failure_message("%s at %d gave %s" % [row, i, got])
				. is_equal_approx(row[2][i], 1e-6)
			)


# FT: FT-SIM-019
# The coverage lobe averages 1 over the sphere for every tightness (tightening moves
# protection, it doesn't add any). Midpoint rule over cos in [-1, 1], 2,000 slices.
func test_coverage_mean_is_one() -> void:
	for k: float in [0.0, 0.5, 2.0, 4.0]:
		var total: float = 0.0
		var n: int = 2000
		for i: int in n:
			total += ShieldSystem.coverage(k, -1.0 + (i + 0.5) * 2.0 / n)
		assert_float(total / n).is_equal_approx(1.0, 1e-4)


# FT: FT-SIM-019
# Hull damage from the same hits orders correct-tight < spread < wrong-tight (P1).
func test_tight_focus_orders_damage() -> void:
	var through: Array[float] = []
	for setup: Array in [[4.0, Vector3.FORWARD], [0.0, Vector3.FORWARD], [4.0, Vector3.BACK]]:
		var w: SimWorld = _world()
		assert_bool(_shield(w, -1, setup[0])).is_true()
		assert_bool(_focus(w, setup[1])).is_true()
		var total: float = 0.0
		for i: int in 10:
			total += _through(w, Vector3.FORWARD, 2e6)
		through.append(total)
	assert_float(through[0]).is_less(through[1])
	assert_float(through[1]).is_less(through[2])


# FT: FT-SIM-019
# Absorption comes off strength, and an empty shield passes the rest.
func test_absorb_limited_by_strength() -> void:
	var w: SimWorld = _world()
	w.shields.strength[0] = 1000.0
	var hit: SimHit = SimHit.new()
	hit.target_id = 0
	hit.from_local = Vector3.FORWARD
	hit.energy = 1e6
	assert_float(ShieldSystem.absorb(w, hit)).is_equal(1e6 - 1000.0)
	assert_float(w.shields.strength[0]).is_equal(0.0)
	assert_float(ShieldSystem.absorb(w, hit)).is_equal(1e6)


# FT: FT-SIM-018
# Engineering sets power (shield pips) and tightness, Helm the direction; invalid
# values are rejected and change nothing. Regeneration follows power.
func test_shield_commands() -> void:
	var w: SimWorld = _world()
	assert_float(w.shields.tightness[0]).is_equal(0.0)
	assert_vector(w.shields.focus[0]).is_equal(Vector3.FORWARD)
	assert_bool(_shield(w, 4, 3.0)).is_true()
	assert_int(w.power.pips[0][PowerSystem.subsystem_index(w.defs[0], SHD)]).is_equal(4)
	assert_float(w.shields.tightness[0]).is_equal(3.0)
	assert_bool(_shield(w, -1, 4.5)).is_false()
	assert_bool(_shield(w, 5, 1.0)).is_false()
	assert_float(w.shields.tightness[0]).is_equal(3.0)
	assert_bool(_focus(w, Vector3(3, 0, 0))).is_true()
	assert_vector(w.shields.focus[0]).is_equal(Vector3.RIGHT)
	assert_bool(_focus(w, Vector3.ZERO)).is_false()
	assert_vector(w.shields.focus[0]).is_equal(Vector3.RIGHT)
	# Regeneration: 5e5 J/s * 4/2 pips over 1 s.
	w.shields.strength[0] = 0.0
	for i: int in 60:
		w.step()
	assert_float(w.shields.strength[0]).is_equal_approx(1e6, 1e-3)
	assert_bool(_shield(w, 0, -1.0)).is_true()
	var before: float = w.shields.strength[0]
	w.step()
	assert_float(w.shields.strength[0]).is_equal(before)
	var c: SetShieldFocusCommand = SetShieldFocusCommand.new()
	c.direction = Vector3.UP
	c.track_id = 2
	var back: SetShieldFocusCommand = SimCommands.from_dict(c.to_dict()) as SetShieldFocusCommand
	assert_vector(back.direction).is_equal(Vector3.UP)
	assert_int(back.track_id).is_equal(2)
	var s: SetShieldCommand = SimCommands.from_dict(SetShieldCommand.new().to_dict())
	assert_object(s).is_instanceof(SetShieldCommand)


# FT: FT-SIM-018
# Tracking keeps the focus on another ship as it moves (D48).
func test_focus_tracks_ship() -> void:
	var w: SimWorld = _world(2)
	assert_bool(_focus(w, Vector3.ZERO, 0)).is_false()
	assert_bool(_focus(w, Vector3.ZERO, 1)).is_true()
	assert_vector(w.shields.focus[0]).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 1e-6)
	w.kin.place(1, 0, 1000.0, 0.0, 0.0)
	w.step()
	assert_vector(w.shields.focus[0]).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 1e-6)
	assert_bool(_focus(w, Vector3.UP)).is_true()
	assert_int(w.shields.track_id[0]).is_equal(-1)


# FT: FT-SIM-031
# &"shield_low" fires once when strength falls to 40 %, and again only after it has
# recovered above 40 %.
func test_low_shield_alert_once_at_40_percent() -> void:
	var w: SimWorld = _world()
	w.shields.strength[0] = 0.41 * 3e7
	w.step()
	assert_int(_lows(w)).is_equal(0)
	# A 1 MJ spread hit absorbs 63 %: about 0.41 - 0.021 = 0.389 of max.
	var hit: SimHit = SimHit.new()
	hit.target_id = 0
	hit.from_local = Vector3.FORWARD
	hit.energy = 1e6
	w.hits.append(hit)
	w.step()
	assert_float(w.shields.strength[0] / 3e7).is_between(0.38, 0.4)
	assert_int(_lows(w)).is_equal(1)
	w.shields.strength[0] = 0.2 * 3e7
	w.step()
	assert_int(_lows(w)).is_equal(0)
	w.shields.strength[0] = 0.5 * 3e7
	w.step()
	assert_int(_lows(w)).is_equal(0)
	w.shields.strength[0] = 0.4 * 3e7 - 10000.0
	w.step()
	assert_int(_lows(w)).is_equal(1)


func _lows(w: SimWorld) -> int:
	var n: int = 0
	for e: SimEvent in w.drain_events():
		if e.kind == &"shield_low":
			n += 1
			assert_float(e.value).is_less_equal(0.4)
	return n


# FT: FT-SIM-017
# No shield, weapon or power definition or table has a frequency field (D28).
func test_no_frequency_mechanic() -> void:
	var objects: Array[Object] = [
		ShieldDef.new(),
		WeaponDef.new(),
		MountDef.new(),
		ShipDef.new(),
		PowerDef.new(),
		SubsystemDef.new(),
		ShieldTable.new(),
		PowerTable.new(),
		MountTable.new(),
		ProjectileTable.new(),
		SetShieldCommand.new(),
		SetShieldFocusCommand.new(),
	]
	for o: Object in objects:
		for p: Dictionary in o.get_property_list():
			assert_str(String(p["name"]).to_lower()).not_contains("freq")
