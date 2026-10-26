class_name SiteDef
extends Resource
## A named site: a point with a radius in the scenario's one wrapping cube (D229,
## FT-SPA-027, FT-MIS-026). Used for callouts, encounter triggers, docking and the director.
## Read-only at runtime (FT-ARC-020); SimWorld.add_site copies it into the SiteTable.
## Units are SI (FT-DAT-013).

## Site kinds, in the order the wire carries them (SitesSection).
const KINDS: Array[StringName] = [&"station", &"nav", &"field", &"derelict"]

## Unique among sites (dimensionless id).
@export var id: StringName = &""
## I18n key of the name every station uses for the site (FT-SPA-027).
@export var name_key: String = ""
## One of KINDS.
@export var kind: StringName = &"nav"
## Point in the cube (m); stored 64-bit in the SiteTable.
@export var pos: Vector3 = Vector3.ZERO
## Radius around the point that counts as "at the site" (m).
@export var radius_m: float = 0.0
@export var dockable: bool = false
## A dockable site docks a ship within this distance of its point (m) ...
@export var dock_range_m: float = 0.0
## ... and at or under this speed (m/s).
@export var dock_max_speed: float = 0.0
## MarketDef id, or &"" for none.
@export var market: StringName = &""
## The faction that holds the site (dimensionless index); 0 for none.
@export var faction: int = 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.id(errors, "name_key", StringName(name_key))
	if not KINDS.has(kind):
		errors.append("kind: must be one of %s, got %s" % [KINDS, kind])
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		errors.append("pos: must be finite, got %s" % pos)
	DefCheck.positive(errors, "radius_m", radius_m)
	DefCheck.in_range(errors, "faction", faction, 0, 30)
	if dockable:
		DefCheck.positive(errors, "dock_range_m", dock_range_m)
		DefCheck.positive(errors, "dock_max_speed", dock_max_speed)
	return errors
