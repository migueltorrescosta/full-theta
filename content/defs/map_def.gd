class_name MapDef
extends Resource
## A scenario's whole map (D229, FT-MIS-024, FT-SIM-035): one wrapping cube with period P
## and the named sites in it. Read-only at runtime (FT-ARC-020).

## Unique among maps (dimensionless id).
@export var id: StringName = &""
## Side of the cube (m); the default is D229's.
@export var period_m: float = 400000.0
## The sites present from the start, in site id order (site 0 first, Kestrel Yard, D205).
@export var sites: Array[SiteDef] = []
## Site ids (SiteDef.id) every crew faction knows at the start (FT-MIS-027).
@export var known_at_start: Array[StringName] = []
## The pool the director opens sites from (OpenSiteCommand).
@export var spawnable: Array[SiteDef] = []
## Travel legs the director may put debris on (D234): [{from, to, debris, count}], with
## from and to site keys and debris the key of a destructible debris EnemyDef (content/enemies)
## that the debris_leg scenario places on the route with spawn_on_leg (D234), count pieces.
@export var legs: Array[Dictionary] = []


## Field problems that need no ships (DefCheck's load gate, FT-DAT-002).
func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if sites.is_empty():
		errors.append("sites: needs at least one site")
	var ids: Dictionary[StringName, bool] = {}
	var all: Array[SiteDef] = all_sites()
	for i: int in all.size():
		var s: SiteDef = all[i]
		if not DefCheck.required(errors, "sites[%d]" % i, s):
			continue
		for e: String in s.validate():
			errors.append("sites[%d].%s" % [i, e])
		if ids.has(s.id):
			errors.append("sites[%d].id: duplicate id %s" % [i, s.id])
		ids[s.id] = true
	for key: StringName in known_at_start:
		if not _has(sites, key):
			errors.append("known_at_start: no site %s" % key)
	for i: int in legs.size():
		var leg: Dictionary = legs[i]
		for end: String in ["from", "to"]:
			if not ids.has(StringName(leg.get(end, &""))):
				errors.append("legs[%d].%s: no site %s" % [i, end, leg.get(end, "")])
		if int(leg.get("count", 0)) < 0:
			errors.append("legs[%d].count: must be >= 0" % i)
	return errors


## Every problem of the map against the scenario's ships: validate(), the period rules
## (period_errors: at least 4 x the longest sensor range, a multiple of 500 m, at most 2^20
## cells) and the spacing rule (D229): two sites at least twice the longest
## sensor range plus both radii apart by minimum image, so a site's contacts never show
## at another.
func errors(ships: Array[ShipDef]) -> Array[String]:
	var out: Array[String] = validate()
	out.append_array(period_errors(ships))
	if not (is_finite(period_m) and period_m > 0.0):
		return out
	var longest: float = 0.0
	for def: ShipDef in ships:
		longest = maxf(longest, def.sensor_range)
	var all: Array[SiteDef] = all_sites()
	for a: int in all.size():
		for b: int in range(a + 1, all.size()):
			if all[a] == null or all[b] == null:
				continue
			var gap: float = _distance(all[a].pos, all[b].pos)
			var least: float = 2.0 * longest + all[a].radius_m + all[b].radius_m
			if gap < least:
				(
					out
					. append(
						(
							"sites %s and %s are %.0f m apart, under %.0f m (2 x sensor range plus radii)"
							% [all[a].id, all[b].id, gap, least]
						)
					)
				)
	return out


## The sites present from the start, then the spawnable pool.
func all_sites() -> Array[SiteDef]:
	var out: Array[SiteDef] = sites.duplicate()
	out.append_array(spawnable)
	return out


## The period rules (FT-SIM-035, D124, D229), the same as SimWorld.period_errors: both are
## PeriodRules.errors.
func period_errors(ships: Array[ShipDef]) -> Array[String]:
	var longest: float = 0.0
	for def: ShipDef in ships:
		longest = maxf(longest, def.sensor_range)
	return PeriodRules.errors(period_m, longest)


## Minimum-image distance (m) between two points of the cube.
func _distance(a: Vector3, b: Vector3) -> float:
	var d: Vector3 = b - a
	return Vector3(_wrap(d.x), _wrap(d.y), _wrap(d.z)).length()


func _wrap(v: float) -> float:
	return fposmod(v + 0.5 * period_m, period_m) - 0.5 * period_m


static func _has(list: Array[SiteDef], key: StringName) -> bool:
	for s: SiteDef in list:
		if s != null and s.id == key:
			return true
	return false
