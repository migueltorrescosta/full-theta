class_name M1Encounter
extends RefCounted
## The Milestone 1 encounter setup (T036, FT-M1-012): the crewed ship (faction 1) and
## one AI enemy (faction 2), hostile to each other, at the origin, SEPARATION apart and bow
## to bow. It keeps its inputs (seed, build id and the already-loaded definitions; the
## sim never loads, FT-ARC-020) so the run reset is build() again: a fresh world, with
## nothing carried over from the old one (FT-GEN-010, FT-MIS-017). The server calls
## build() to start the run and again to reset it. Space wraps with period
## site_period (FT-SIM-035, D229), checked by validate(); build() refuses a bad one.

const PLAYER_FACTION: int = 1
const ENEMY_FACTION: int = 2
## Ship ids in the built world.
const PLAYER_SHIP: int = 0
const ENEMY_SHIP: int = 1
## Distance from the player ship (at the origin) to the enemy, which sits
## ahead of it on -Z (m).
const SEPARATION: float = 5000.0

var world_seed: int
var build_id: String
var player: ShipDef
var enemy: EnemyDef
## Side of the wrapping cube (m, FT-SIM-035, D229).
var site_period: float
## Science tuning for the built worlds (E01); null leaves the Science commands refused.
var science: ScienceDef
## The hazards of the built worlds (D208, D220), already loaded; at most
## HazardSystem.MAX_HAZARDS, which validate() checks.
var hazards: Array[HazardDef] = []


func _init(
	seed_value: int,
	build: String,
	player_def: ShipDef,
	enemy_def: EnemyDef,
	period: float = Kinematics.DEFAULT_PERIOD
) -> void:
	world_seed = seed_value
	build_id = build
	player = player_def
	enemy = enemy_def
	site_period = period


## Site 0, Kestrel Yard (D205, D229), the one named site of the M1 map: at the origin, where the
## player starts, dockable.
static func kestrel_yard() -> SiteDef:
	var site: SiteDef = SiteDef.new()
	site.id = &"kestrel_yard"
	site.name_key = "site.kestrel_yard"
	site.kind = &"station"
	site.radius_m = 3000.0
	site.dockable = true
	site.dock_range_m = 1500.0
	site.dock_max_speed = 10.0
	return site


## Why the setup can't be built, or [] (site_period against the ships' sensor ranges
## and the broadphase cells, SimWorld.period_errors).
func validate() -> Array[String]:
	var ships: Array[ShipDef] = [player, enemy.ship]
	var errors: Array[String] = SimWorld.period_errors(site_period, ships)
	if hazards.size() > HazardSystem.MAX_HAZARDS:
		errors.append(
			"%d hazards, at most %d are supported" % [hazards.size(), HazardSystem.MAX_HAZARDS]
		)
	return errors


## A new world at tick 0 holding the encounter, or null when validate() reports errors.
## Calling it again is the run reset.
func build() -> SimWorld:
	if not validate().is_empty():
		return null
	var world: SimWorld = SimWorld.new(world_seed, build_id, site_period)
	world.science_def = science
	world.hazards = hazards.duplicate()
	world.add_site(kestrel_yard())
	world.set_relation(PLAYER_FACTION, ENEMY_FACTION, SimWorld.Relation.HOSTILE)
	world.spawn_ship(player, PLAYER_FACTION)
	var facing_player: Quaternion = Quaternion(Vector3.UP, PI)
	world.spawn_enemy(enemy, ENEMY_FACTION, Vector3(0.0, 0.0, -SEPARATION), facing_player)
	return world
