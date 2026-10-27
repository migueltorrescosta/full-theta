class_name SiteView
extends RefCounted
## A value copy of one named site (FT-ARC-016, FT-DAT-009, FT-SPA-027).

var id: int = -1
var key: StringName = &""
var name_key: String = ""
var kind: StringName = &""
## Cube offset of the site's point (m, 64-bit values: x, y, z).
var pos: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var radius_m: float = 0.0
var dockable: bool = false
## Factions that know the site.
var known_by: PackedInt32Array = PackedInt32Array()
