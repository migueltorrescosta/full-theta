class_name LoadEncounter
extends M1Encounter
## The 64-connection load scene (#11, FT-GEN-003, FT-NET-040): `crew_ships` crewable
## ships of one co-op faction plus AI raiders up to `world_ships`, at one site: 6 + 6
## for the gate, 6 + 94 (the S6/S9 envelope) for the stress run (D160). TEST AND DEV
## ONLY (`--load-ships`): the real multi-ship lobby and scenarios replace it (#11, E11).
##
## The crewed ships sit near the middle of a cube of side ARENA; the raiders are spread
## over it, split between two AI factions hostile to each other and to the crew, so
## they keep fighting and projectiles fly for the whole run. With crew_hostile false
## the crew faction is neutral to both and its ships are left alone. All
## positions come from a RandomNumberGenerator seeded with the world seed, so a build is
## reproducible. It extends M1Encounter only so NetServer takes it unchanged.

const CREW_FACTION: int = 1
const RAIDER_FACTIONS: Array[int] = [2, 3]
## Side of the cube the ships start in (m); S6/S9 used a 4 km cube.
const ARENA: float = 4000.0
## The crewed ships start within this distance of the middle on each axis (m).
const CREW_SPREAD: float = 500.0

var crew_ships: int
var world_ships: int
var crew_hostile: bool


func _init(
	seed_value: int,
	build: String,
	player_def: ShipDef,
	enemy_def: EnemyDef,
	crew: int = 6,
	total: int = 12,
	hostile: bool = true,
	period: float = Kinematics.DEFAULT_PERIOD
) -> void:
	super(seed_value, build, player_def, enemy_def, period)
	crew_ships = crew
	world_ships = maxi(total, crew)
	crew_hostile = hostile


func validate() -> Array[String]:
	var errors: Array[String] = super()
	if crew_ships < 1:
		errors.append("crew_ships must be at least 1, got %d" % crew_ships)
	return errors


## A new world at tick 0: crewed ships 0 .. crew_ships - 1, then the raiders.
func build() -> SimWorld:
	if not validate().is_empty():
		return null
	var world: SimWorld = SimWorld.new(world_seed, build_id, site_period)
	world.science_def = science
	world.set_relation(RAIDER_FACTIONS[0], RAIDER_FACTIONS[1], SimWorld.Relation.HOSTILE)
	if not crew_hostile:
		for f: int in RAIDER_FACTIONS:
			world.set_relation(CREW_FACTION, f, SimWorld.Relation.NEUTRAL)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed
	for i: int in crew_ships:
		world.spawn_ship(player, CREW_FACTION, SITE, _point(rng, CREW_SPREAD), _rotation(rng))
	for i: int in world_ships - crew_ships:
		var f: int = RAIDER_FACTIONS[i % RAIDER_FACTIONS.size()]
		world.spawn_enemy(enemy, f, SITE, _point(rng, ARENA * 0.5), _rotation(rng))
	return world


static func _point(rng: RandomNumberGenerator, half: float) -> Vector3:
	return Vector3(
		rng.randf_range(-half, half), rng.randf_range(-half, half), rng.randf_range(-half, half)
	)


static func _rotation(rng: RandomNumberGenerator) -> Quaternion:
	var axis: Vector3 = _point(rng, 1.0)
	if axis.length() < 1e-3:
		axis = Vector3.UP
	return Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
