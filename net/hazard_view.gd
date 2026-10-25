class_name HazardView
extends RefCounted
## The sim hazards a faction knows of, as the RELAY block lists them (D208, FT-RLY-001,
## P4, P11): where each is now and when it reaches the ship. Relay draws them on its map
## and Engineering's countdown reads the forecast. Only hazards on the ship's site that
## HazardSystem.known_to the ship's faction are listed (sensors or a probe's bubble).

## Row shapes (u8 on the wire).
const ZONE: int = 0
const SHELL: int = 1
const PLANE: int = 2

## Rows a block may hold (a row count is one byte).
const MAX_ROWS: int = 32


## The rows for a ship: {id (the hazard's index in SimWorld.hazards), shape, pos (site-local
## m: a zone's or shell's centre, the point of a plane nearest the ship), radius (m: the
## zone's or the shell's now, 0 for a plane), dir (unit vector: a plane's travel, else 0),
## eta (s until it reaches the ship at its present velocity, -1 when it is not coming)}.
static func rows(world: SimWorld, ship: int) -> Array:
	var out: Array = []
	var faction: int = world.faction_of(ship)
	var t: float = world.tick * SimWorld.DT
	for i: int in world.hazards.size():
		var h: HazardDef = world.hazards[i]
		if h.site != world.kin.site[ship] or not HazardSystem.known_to(world, faction, i):
			continue
		if out.size() >= MAX_ROWS:
			break
		var row: Dictionary = {"id": i, "eta": HazardSystem.eta(world, ship, i)}
		var since: float = maxf(0.0, t - h.start_s)
		if h.is_front() and h.shape == HazardDef.Shape.PLANE:
			var gap: float = HazardSystem.edge_distance(
				h, HazardSystem.ship_offset(world, ship, h), t
			)
			row.merge({"shape": PLANE, "pos": _ship_at(world, ship) - h.direction * gap})
			row.merge({"radius": 0.0, "dir": h.direction})
		else:
			var r: float = h.radius + (h.speed * since if h.is_front() else 0.0)
			row.merge({"shape": SHELL if h.is_front() else ZONE, "pos": h.center})
			row.merge({"radius": r, "dir": Vector3.ZERO})
		out.append(row)
	return out


static func _ship_at(world: SimWorld, ship: int) -> Vector3:
	var p: PackedFloat64Array = world.kin.point_at(ship, Vector3.ZERO)
	return Vector3(p[0], p[1], p[2])
