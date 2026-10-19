extends GdUnitTestSuite
## T034: per-faction contact knowledge and callsigns. Distances are whole metres well
## clear of the M1 ranges (corvette senses 20 km and identifies at 8 km; raider 15 km
## and 6 km), so no tolerance is needed.

const BLUE: int = 1
const RED: int = 2
const GREEN: int = 3


func _place(w: SimWorld, id: int, x: float, z: float = 0.0) -> void:
	w.kin.place(id, w.kin.site[id], x, 0.0, z)


# FT: FT-ARC-013
# Each faction holds its own knowledge: at 18 km the corvette (20 km sensors) detects
# the raider, but the raider (15 km) does not detect the corvette; at 12 km both do.
func test_detection_is_per_faction() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(18000, 0, 0))
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, RED, blue)).is_false()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, blue)).is_true()
	assert_array(KnowledgeSystem.contacts(w, BLUE)).is_equal(PackedInt32Array([red]))
	assert_array(KnowledgeSystem.contacts(w, RED)).is_empty()
	_place(w, red, 12000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, RED, blue)).is_true()
	assert_int(w.knowledge.size()).is_equal(2)


# FT: FT-ARC-013
# Ships at another site, destroyed ships and destroyed observers never detect or count.
func test_site_and_destroyed_ships() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 1, Vector3(100, 0, 0))
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_false()
	var near: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(100, 0, 0))
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, near)).is_true()
	w.kin.alive[near] = 0
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, near)).is_false()
	w.kin.alive[blue] = 0
	w.kin.place(red, 0, 50.0, 0.0, 0.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_false()


# FT: FT-ARC-013
# sensor_range comes from the ship definition (copied def with a 5 km range).
func test_sensor_range_from_definition() -> void:
	var short: ShipDef = TestDefs.corvette().duplicate(true)
	short.sensor_range = 5000.0
	short.identify_range = 1000.0
	var w: SimWorld = SimWorld.new(1)
	w.spawn_ship(short, BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(0, 0, -6000))
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_false()
	_place(w, red, 0.0, -4000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_true()


# FT: FT-ARC-013
# Sensor range scales with the sensors' effectiveness (real DamageSystem): at 10 km the
# raider is detected; with the corvette's sensors at a quarter health (effectiveness 0.3
# on the M1 curve, so 20 km * 0.3 = 6 km) the contact is lost, and at 5 km it is back.
func test_damaged_sensors_shrink_range() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(10000, 0, 0))
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_true()
	w.drain_events()
	DamageSystem.damage_subsystem(w, blue, SimFixture.sub_index(w, blue, &"sensors"), 1.5e7)
	assert_float(DamageSystem.effectiveness(w, blue, &"sensors")).is_equal_approx(0.3, 1e-6)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_false()
	var lost: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"contact_lost")
	assert_int(lost.size()).is_equal(1)
	assert_int(lost[0].other_id).is_equal(red)
	_place(w, red, 5000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_true()


# FT: FT-SPA-001, FT-SPA-002
# Prefix by known allegiance: U before identification (beyond 8 km), then by relation
# H, N or F; identification is kept when the contact moves back out. The number stays.
func test_callsign_prefix_by_allegiance() -> void:
	var w: SimWorld = SimWorld.new(1)
	w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(12000, 0, 0))
	w.step()
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("U1")
	assert_bool(KnowledgeSystem.is_identified(w, BLUE, red)).is_false()
	_place(w, red, 5000.0)
	w.step()
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("H1")
	w.set_relation(BLUE, RED, SimWorld.Relation.NEUTRAL)
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("N1")
	w.set_relation(BLUE, RED, SimWorld.Relation.FRIENDLY)
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("F1")
	_place(w, red, 12000.0)
	w.step()
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("F1")


# FT: FT-SPA-001, FT-SPA-002
# Numbers follow first detection per faction and never change: lost and re-detected,
# a contact keeps its number, and the next new contact gets the next number.
func test_number_never_changes_after_loss() -> void:
	var w: SimWorld = SimWorld.new(1)
	w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var a: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(5000, 0, 0))
	var b: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(30000, 0, 0))
	var c: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(40000, 0, 0))
	w.step()
	_place(w, b, -5000.0)
	w.step()
	assert_str(KnowledgeSystem.callsign(w, BLUE, a)).is_equal("H1")
	assert_str(KnowledgeSystem.callsign(w, BLUE, b)).is_equal("H2")
	assert_str(KnowledgeSystem.callsign(w, BLUE, c)).is_equal("")
	_place(w, a, 50000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, a)).is_false()
	assert_str(KnowledgeSystem.callsign(w, BLUE, a)).is_equal("H1")
	_place(w, c, 0.0, 5000.0)
	w.step()
	_place(w, a, 3000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, a)).is_true()
	assert_str(KnowledgeSystem.callsign(w, BLUE, a)).is_equal("H1")
	assert_str(KnowledgeSystem.callsign(w, BLUE, b)).is_equal("H2")
	assert_str(KnowledgeSystem.callsign(w, BLUE, c)).is_equal("H3")


# FT: FT-SPA-002, FT-ARC-013
# Callsigns are per faction: allied ships (one faction) share them, whichever ship sees
# the contact; another faction numbers the same ships in its own detection order. Own
# ships go by ship name.
func test_callsigns_per_faction() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue_a: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var blue_b: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0, Vector3(100000, 0, 0))
	var green: int = w.spawn_ship(TestDefs.corvette(), GREEN, 0, Vector3(95000, 0, 0))
	var red_x: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(3000, 0, 0))
	var red_y: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(97000, 0, 0))
	w.step()
	# BLUE detects red_x (via blue_a), green, red_y (via blue_b) in contact id order.
	assert_str(KnowledgeSystem.callsign(w, BLUE, green)).is_equal("H1")
	assert_str(KnowledgeSystem.callsign(w, BLUE, red_x)).is_equal("H2")
	assert_str(KnowledgeSystem.callsign(w, BLUE, red_y)).is_equal("H3")
	# GREEN sees blue_b and red_y only.
	assert_str(KnowledgeSystem.callsign(w, GREEN, blue_b)).is_equal("H1")
	assert_str(KnowledgeSystem.callsign(w, GREEN, red_y)).is_equal("H2")
	assert_str(KnowledgeSystem.callsign(w, GREEN, red_x)).is_equal("")
	assert_bool(KnowledgeSystem.is_detected(w, GREEN, blue_a)).is_false()
	assert_str(KnowledgeSystem.callsign(w, BLUE, blue_b)).is_equal("Corvette")


# FT: FT-ARC-013, FT-SPA-001
# contact_detected / contact_lost go to the observing faction: ship_id is the observing
# ship that sees it (here only the second blue ship is in range), other_id the contact,
# value the number and tag the callsign.
func test_events_keyed_to_observing_faction() -> void:
	var w: SimWorld = SimWorld.new(1)
	w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var blue_b: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0, Vector3(-5000, 0, 0))
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(-22000, 0, 0))
	w.step()
	var found: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"contact_detected")
	assert_int(found.size()).is_equal(1)
	assert_int(found[0].ship_id).is_equal(blue_b)
	assert_int(found[0].faction).is_equal(BLUE)
	assert_int(found[0].other_id).is_equal(red)
	assert_float(found[0].value).is_equal(1.0)
	assert_str(String(found[0].tag)).is_equal("U1")
	w.step()
	assert_array(w.drain_events()).is_empty()
	_place(w, red, -40000.0)
	w.step()
	var lost: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"contact_lost")
	assert_int(lost.size()).is_equal(1)
	assert_int(lost[0].faction).is_equal(BLUE)
	assert_int(lost[0].other_id).is_equal(red)


# FT: FT-SPA-001, FT-ARC-013
# Per-ship reset keeps the faction's rows and numbers; the reset ship is undetected
# until the next step re-detects it, with the same callsign. Other rows are untouched.
func test_reset_ship_keeps_numbers() -> void:
	var w: SimWorld = SimWorld.new(1)
	var blue: int = w.spawn_ship(TestDefs.corvette(), BLUE, 0)
	var red: int = w.spawn_ship(TestDefs.raider(), RED, 0, Vector3(5000, 0, 0))
	w.step()
	var before: Array = w.knowledge.columns()
	assert_int(w.knowledge.size()).is_equal(2)
	w.reset_ship(red, 0, Vector3(4000, 0, 0))
	assert_int(w.knowledge.size()).is_equal(2)
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_false()
	assert_bool(KnowledgeSystem.is_detected(w, RED, blue)).is_true()
	assert_str(KnowledgeSystem.callsign(w, BLUE, red)).is_equal("H1")
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, red)).is_true()
	assert_array(w.knowledge.columns()).is_equal(before)
