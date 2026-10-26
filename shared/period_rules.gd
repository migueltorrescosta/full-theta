class_name PeriodRules
extends RefCounted
## The rules a scenario's cube period P must meet (FT-SIM-035, D124, D229), shared by
## MapDef (the load check) and SimWorld (the world check) so they cannot drift apart.
## Pure; the broadphase cell sizes are CollisionSystem's, which takes them from here.

## Projectile broadphase cell (m, S6).
const CELL: float = 250.0
## Ship-pair broadphase cell (m).
const PAIR_CELL: float = 500.0
## The cube's period must be at least this many times the longest sensor range.
const PERIOD_PER_SENSOR_RANGE: int = 4
## Most broadphase cells per axis (2^20), so CollisionSystem's int cell keys stay below
## 2^60: a period of at most 2^20 * CELL (262 144 km).
const MAX_CELLS_PER_AXIS: int = 1 << 20


## Why a period (m) doesn't suit ships whose longest sensor range is `longest` (m), or []:
## finite and positive, a whole number of both broadphase cells and at most
## MAX_CELLS_PER_AXIS of either, and at least PERIOD_PER_SENSOR_RANGE times the longest
## sensor range, so a ship is never seen around the seam (or the same ship twice).
static func errors(period: float, longest: float) -> Array[String]:
	var out: Array[String] = []
	if not (is_finite(period) and period > 0.0):
		out.append("site period must be finite and positive, got %s" % period)
		return out
	for cell: float in [CELL, PAIR_CELL]:
		if fposmod(period, cell) != 0.0:
			out.append("site period %.1f m is not a multiple of %.1f m" % [period, cell])
		if period / cell > MAX_CELLS_PER_AXIS:
			out.append(
				"site period %.1f m is over %d cells of %.1f m" % [period, MAX_CELLS_PER_AXIS, cell]
			)
	if period < PERIOD_PER_SENSOR_RANGE * longest:
		out.append(
			(
				"site period %.1f m is under %d x the longest sensor range %.1f m"
				% [period, PERIOD_PER_SENSOR_RANGE, longest]
			)
		)
	return out
