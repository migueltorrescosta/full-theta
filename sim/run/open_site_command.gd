class_name OpenSiteCommand
extends ServerCommand
## Opens a site of the map's spawnable pool (E07, D80, FT-MIS-026): the director's site
## spawn. The SiteTable gives it the next site id; opening one that is open is
## accepted and changes nothing. Emits &"site_opened" (other_id the site, tag the key).

var site_key: StringName = &""


func kind() -> StringName:
	return &"open_site"


func apply(world: SimWorld) -> bool:
	var before: int = world.sites.size()
	var site: int = world.sites.open(world, site_key)
	if site < 0:
		return false
	if world.sites.size() > before:
		world.emit(&"site_opened", -1, site, 0.0, Vector3.ZERO, site_key)
	return true
