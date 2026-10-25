class_name HazardEta
extends RefCounted
## Hazard countdowns on Engineering (P11, FT-ENG-008, D208): the server's forecast of each
## sim hazard the faction knows (the RELAY block's `eta`). Zones Relay marks are map
## annotations, not hazards, and carry no countdown.


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
