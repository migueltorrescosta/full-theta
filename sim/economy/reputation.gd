class_name Reputation
extends RefCounted
## Reputation changes drawn from data-defined distributions (FT-MIS-019, FT-MIS-020,
## FT-DAT-010, D34). A draw uses the world's seeded "reputation" stream, so a run replays
## to the same standings, and one draw per interaction keeps the stream aligned.


## One draw from the distribution.
static func draw(world: SimWorld, def: RepDistDef) -> float:
	var rng: RandomNumberGenerator = world.rng.stream(&"reputation")
	var span: float = def.hi - def.lo
	match def.kind:
		&"triangular":
			var u: float = rng.randf()
			if span <= 0.0:
				return def.lo
			var cut: float = (def.mode - def.lo) / span
			if u < cut:
				return def.lo + sqrt(u * span * (def.mode - def.lo))
			return def.hi - sqrt((1.0 - u) * span * (def.hi - def.mode))
		&"normal_clamped":
			return clampf(rng.randfn(def.mode, span / 6.0), def.lo, def.hi)
	return def.lo + rng.randf() * span


## Draws from the distribution `dist_id` and adds it to faction's standing with other;
## returns the change (0 for an unknown distribution or a negative faction, with no draw).
## `ship` is the crew ship the change is reported to (event `rep_changed`: value the
## change, other_id the faction).
static func change(
	world: SimWorld, ship: int, faction: int, other: int, dist_id: StringName
) -> float:
	var def: RepDistDef = world.rep_dists.get(dist_id)
	if def == null or faction < 0 or other < 0:
		return 0.0
	var delta: float = draw(world, def)
	apply(world, faction, other, delta)
	world.emit(&"rep_changed", ship, other, delta, Vector3.ZERO, dist_id)
	return delta


## Adds delta to faction's standing with other, clamped to the table's range.
static func apply(world: SimWorld, faction: int, other: int, delta: float) -> void:
	var t: ReputationTable = world.reputation
	var r: int = t.ensure(faction, other)
	t.value[r] = clampf(t.value[r] + delta, ReputationTable.MIN, ReputationTable.MAX)


## [lo, hi] of the distribution when its data marks the range visible, else [] (FT-MIS-020).
static func visible_range(world: SimWorld, dist_id: StringName) -> Array[float]:
	var def: RepDistDef = world.rep_dists.get(dist_id)
	var out: Array[float] = []
	if def != null and def.visible:
		out.assign([def.lo, def.hi])
	return out
