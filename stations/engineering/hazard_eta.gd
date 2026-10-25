class_name HazardEta
extends RefCounted
## Hazard countdowns on Engineering (P11, FT-ENG-008): how long until the ship reaches the
## edge of a hazard zone Relay marked, at its present velocity. Worked out on the client from
## the zones every pick of the ship receives (they are MARK items, shown at every difficulty)
## and the ship's own motion, so the toggle only decides whether Engineering shows it.


## Seconds until the ship reaches the edge of a zone of `radius` (m) whose centre is `offset`
## (m) away from it, moving at `velocity` (m/s), both in world axes: 0 inside the zone, -1
## when the ship isn't closing on it.
static func eta(offset: Vector3, radius: float, velocity: Vector3) -> float:
	var distance: float = offset.length() - radius
	if distance <= 0.0:
		return 0.0
	var closing: float = velocity.dot(offset.normalized())
	if closing < 0.5:
		return -1.0
	return distance / closing


## The soonest countdown over the hazard zones at the ship's site (CrewState.zones), or -1:
## `offsets` maps a zone id to the offset (m) from the ship to its centre.
static func soonest(zones: Array, offsets: Dictionary, velocity: Vector3) -> float:
	var best: float = -1.0
	for z: Dictionary in zones:
		if z["kind"] != "hazard" or not offsets.has(z["id"]):
			continue
		var t: float = eta(offsets[z["id"]], float(z["radius"]), velocity)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## The soonest forecast over the RELAY block's sim hazards (rows with `eta`), or -1.
static func forecast(rows: Array) -> float:
	var best: float = -1.0
	for row: Dictionary in rows:
		best = sooner(best, float(row["eta"]))
	return best


## The sooner of two countdowns, -1 meaning none.
static func sooner(a: float, b: float) -> float:
	if a < 0.0:
		return b
	return a if b < 0.0 else minf(a, b)
