class_name DockCommand
extends SimCommand
## Docks the ship at a named site (FT-HLM-013, D229). The site must be known to the ship's
## faction and dockable, the ship within its dock_range_m of the point and at or under its
## dock_max_speed, and neither jumping nor docked already. JumpSystem holds a docked ship
## at the point; UndockCommand lets it go. Emits &"docked" (value: the site id).

var site_id: int = -1


func kind() -> StringName:
	return &"helm_dock"


func apply(world: SimWorld) -> bool:
	var helm: HelmTable = world.helm
	var sites: SiteTable = world.sites
	if helm.docked_site[ship_id] >= 0 or helm.jump_left[ship_id] > 0:
		return false
	if not sites.is_known(site_id, world.faction_of(ship_id)) or sites.dockable[site_id] != 1:
		return false
	if SiteTable.offset_to(world, ship_id, site_id).length() > sites.dock_range[site_id]:
		return false
	if world.kin.vel[ship_id].length() > sites.dock_max_speed[site_id]:
		return false
	helm.docked_site[ship_id] = site_id
	world.emit(&"docked", ship_id, -1, float(site_id))
	return true
