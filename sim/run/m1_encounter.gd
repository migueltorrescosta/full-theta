class_name M1Encounter
extends RefCounted
## The Milestone 1 encounter setup (T036, FT-M1-012): the crewed ship (faction 1) and
## one AI enemy (faction 2), hostile to each other, at site 0, SEPARATION apart and bow
## to bow. It keeps its inputs (seed, build id and the already-loaded definitions; the
## sim never loads, FT-ARC-020) so the run reset is build() again: a fresh world, with
## nothing carried over from the old one (FT-GEN-010, FT-MIS-017). The server calls
## build() to start the run and again to reset it.

const PLAYER_FACTION: int = 1
const ENEMY_FACTION: int = 2
const SITE: int = 0
## Ship ids in the built world.
const PLAYER_SHIP: int = 0
const ENEMY_SHIP: int = 1
## Distance from the player ship (at the site's local origin) to the enemy, which sits
## ahead of it on -Z (m).
const SEPARATION: float = 5000.0

var world_seed: int
var build_id: String
var player: ShipDef
var enemy: EnemyDef
## The site's origin in the scenario map (m, x, y, z); recorded for maps and jumps
## only, never read per tick (D98).
var site_origin: PackedFloat64Array


func _init(
	seed_value: int,
	build: String,
	player_def: ShipDef,
	enemy_def: EnemyDef,
	origin: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
) -> void:
	world_seed = seed_value
	build_id = build
	player = player_def
	enemy = enemy_def
	site_origin = origin


## A new world at tick 0 holding the encounter. Calling it again is the run reset.
func build() -> SimWorld:
	var world: SimWorld = SimWorld.new(world_seed, build_id)
	world.site_origins[SITE] = site_origin.duplicate()
	world.set_relation(PLAYER_FACTION, ENEMY_FACTION, SimWorld.Relation.HOSTILE)
	world.spawn_ship(player, PLAYER_FACTION, SITE)
	var facing_player: Quaternion = Quaternion(Vector3.UP, PI)
	world.spawn_enemy(enemy, ENEMY_FACTION, SITE, Vector3(0.0, 0.0, -SEPARATION), facing_player)
	return world
