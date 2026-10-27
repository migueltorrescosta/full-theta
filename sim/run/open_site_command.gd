class_name OpenSiteCommand
extends ServerCommand
## Opens a site of the map's spawnable pool (E07, D80, FT-MIS-026): the director's site
## spawn. The SiteTable gives it the next site id; opening one that is open is
## accepted and changes nothing. Emits &"site_opened" (other_id the site, tag the key).

var site_key: StringName = &""
## RACE (#11, M4-Q5): when set, opens this ship's own copy of the site (SiteTable.open_copy).
var for_ship: int = -1


func kind() -> StringName:
	return &"open_site"


func apply(world: SimWorld) -> bool:
	var before: int = world.sites.size()
	var site: int = -1
	if for_ship >= 0:
		if for_ship >= world.ship_count():
			return false
		site = world.sites.open_copy(world, site_key, for_ship)
	else:
		site = world.sites.open(world, site_key)
	if site < 0:
		return false
	if world.sites.size() > before:
		world.emit(&"site_opened", -1, site, 0.0, Vector3.ZERO, world.sites.key_of(site))
	result_id = site
	return true
