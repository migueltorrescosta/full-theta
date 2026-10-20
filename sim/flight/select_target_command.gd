class_name SelectTargetCommand
extends SimCommand
## Selects Helm's target for face and approach: a ship (contact) when target_ship >= 0,
## else a site-local point (mark or site) when site >= 0, else nothing. Rejects its own
## ship, an unknown ship id, a ship its faction doesn't detect (FT-ARC-013, FT-SIM-028)
## and a non-finite point; a point off the site's cube is wrapped onto it (FT-SIM-035,
## D124).

## Ship id to select, or -1.
var target_ship: int = -1
## Site of the point to select, or -1.
var site: int = -1
## Site-local offset of the point (m, 64-bit, D104).
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


func kind() -> StringName:
	return &"helm_select_target"


func apply(world: SimWorld) -> bool:
	var helm: HelmTable = world.helm
	var kind_value: int = HelmTable.Target.NONE
	var p: PackedFloat64Array = world.kin.wrap_point(x, y, z)
	if target_ship >= 0:
		if target_ship == ship_id or target_ship >= world.ship_count():
			return false
		if not KnowledgeSystem.is_detected(world, world.faction_of(ship_id), target_ship):
			return false
		kind_value = HelmTable.Target.SHIP
	elif site >= 0:
		if p.is_empty():
			return false
		kind_value = HelmTable.Target.POINT
	var is_point: bool = kind_value == HelmTable.Target.POINT
	helm.target_kind[ship_id] = kind_value
	helm.target_ship[ship_id] = target_ship if kind_value == HelmTable.Target.SHIP else -1
	helm.target_site[ship_id] = site if is_point else -1
	helm.target_x[ship_id] = p[0] if is_point else 0.0
	helm.target_y[ship_id] = p[1] if is_point else 0.0
	helm.target_z[ship_id] = p[2] if is_point else 0.0
	return true
