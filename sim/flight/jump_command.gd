class_name JumpCommand
extends SimCommand
## Starts the jump drive's spool toward a named site or a free point of the cube
## (FT-SIM-034, FT-HLM-016, D229). Rejected unless the ship can jump (ShipDef.jump_spool_s),
## is neither docked nor already jumping, has the propellant, the target exists (a site
## its faction knows, or a finite point) and Helm faces it within
## ShipDef.jump_face_tolerance_rad. It takes the propellant at once and emits &"jump_spool"
## (value: the target site id or -1, tag: the site the ship is at now or "-1"); JumpSystem
## moves the ship when the spool ends.

## SITE or MARK (HelmTable.JumpKind).
var target_kind: int = HelmTable.JumpKind.SITE
## The site id for SITE.
var target_id: int = -1
## The point in the cube for MARK (m, 64-bit, D104).
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


func kind() -> StringName:
	return &"helm_jump"


func apply(world: SimWorld) -> bool:
	if target_kind != HelmTable.JumpKind.SITE and target_kind != HelmTable.JumpKind.MARK:
		return false
	var def: ShipDef = world.defs[ship_id]
	var helm: HelmTable = world.helm
	var busy: bool = helm.jump_left[ship_id] > 0 or helm.docked_site[ship_id] >= 0
	if def.jump_spool_s <= 0.0 or busy or world.kin.propellant[ship_id] < def.jump_propellant_kg:
		return false
	var at: PackedFloat64Array = _target_point(world)
	if at.is_empty():
		return false
	var offset: Vector3 = world.kin.relative_to_point(ship_id, at[0], at[1], at[2])
	if offset.length() < 1.0:
		return false
	if world.kin.forward(ship_id).angle_to(offset) > def.jump_face_tolerance_rad:
		return false
	var site: int = target_id if target_kind == HelmTable.JumpKind.SITE else -1
	world.kin.propellant[ship_id] -= def.jump_propellant_kg
	world.kin.propellant_used[ship_id] += def.jump_propellant_kg
	helm.jump_left[ship_id] = ceili(def.jump_spool_s * SimWorld.HZ)
	helm.jump_kind[ship_id] = target_kind
	helm.jump_target[ship_id] = site
	helm.jump_x[ship_id] = at[0]
	helm.jump_y[ship_id] = at[1]
	helm.jump_z[ship_id] = at[2]
	helm.jump_seen_by[ship_id] = EncounterSystem.hostile_seeing(world, ship_id)
	var origin: StringName = StringName(str(SiteTable.at_site(world, ship_id)))
	world.emit(&"jump_spool", ship_id, -1, float(site), Vector3.ZERO, origin)
	return true


## The target point [x, y, z] in the cube, or empty when the target doesn't exist or isn't
## known to the ship's faction.
func _target_point(world: SimWorld) -> PackedFloat64Array:
	if target_kind == HelmTable.JumpKind.SITE:
		var sites: SiteTable = world.sites
		if not sites.is_known(target_id, world.faction_of(ship_id)):
			return PackedFloat64Array()
		return PackedFloat64Array(
			[sites.pos_x[target_id], sites.pos_y[target_id], sites.pos_z[target_id]]
		)
	return world.kin.wrap_point(x, y, z)
