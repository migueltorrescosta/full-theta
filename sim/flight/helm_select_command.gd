class_name HelmSelectCommand
extends SimCommand
## Helm's selection for face and approach (D397): a contact (a ship) when contact >= 0,
## else a named site when site_id >= 0 (FT-HLM-016, FT-SPA-015), else a point in the cube
## (mark) when point is set, else nothing. Rejects its own
## ship, an unknown ship id, a ship its faction doesn't detect (FT-ARC-013, FT-SIM-028)
## and a non-finite point; a point off the cube is wrapped onto it (FT-SIM-035,
## D124).

## Ship id to select, or -1.
var contact: int = -1
## Site id to select (FT-SPA-027), or -1.
var site_id: int = -1
## Whether to select the point (x, y, z) rather than nothing.
var point: bool = false
## Offset of the point in the cube (m, 64-bit, D104).
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


func kind() -> StringName:
	return &"helm_select"


func apply(world: SimWorld) -> bool:
	var helm: HelmTable = world.helm
	var kind_value: int = HelmTable.Selection.NONE
	var p: PackedFloat64Array = world.kin.wrap_point(CubePoint.make(x, y, z))
	if contact >= 0:
		if contact == ship_id or contact >= world.ship_count():
			return false
		if not KnowledgeSystem.is_detected(world, world.faction_of(ship_id), contact):
			return false
		kind_value = HelmTable.Selection.SHIP
	elif site_id >= 0:
		if not world.sites.is_known(site_id, world.faction_of(ship_id)):
			return false
		kind_value = HelmTable.Selection.SITE
	elif point:
		if p.is_empty():
			return false
		kind_value = HelmTable.Selection.POINT
	var is_point: bool = kind_value == HelmTable.Selection.POINT
	helm.sel_kind[ship_id] = kind_value
	helm.sel_contact[ship_id] = contact if kind_value == HelmTable.Selection.SHIP else -1
	helm.sel_site[ship_id] = site_id if kind_value == HelmTable.Selection.SITE else -1
	helm.sel_x[ship_id] = p[0] if is_point else 0.0
	helm.sel_y[ship_id] = p[1] if is_point else 0.0
	helm.sel_z[ship_id] = p[2] if is_point else 0.0
	return true
