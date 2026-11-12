class_name Callout
extends RefCounted
## Spoken spatial callouts (spec §6.1, D45, D97), shared by the sim and every client
## (FT-ARC-021): pure functions of plain values, naming nothing outside shared/.
##
## Frame rule (FT-SPA-026): the clock and the words level, high, low, overhead and under
## are always ship frame, computed from an offset in the ship's local frame (-Z bow,
## +X starboard, +Y up). Space has no privileged up and no world grid (D124: sites wrap
## as a 3-torus), so there are no world-frame words.

## Height words switch from level to high/low at this elevation (FT-SPA-004).
const LEVEL_DEG: float = 15.0
## Above this elevation only overhead/under, without a clock (FT-SPA-003, NAV-7).
const POLE_DEG: float = 60.0
## Range bands (m): close below CLOSE_DISTANCE, far above FAR_DISTANCE, mid in between (FT-SPA-003).
const CLOSE_DISTANCE: float = 1000.0
const FAR_DISTANCE: float = 10000.0

## Elevations (degrees) of the heights -2 (under), -1 (low), 0 (level), 1 (high), 2 (overhead):
## each inside its band of height_word, so clock_height(direction(c, h)) names c and h.
const HEIGHT_DEG: Array[float] = [-75.0, -35.0, 0.0, 35.0, 75.0]


## Bearing 0..360, clockwise from the bow in the deck plane (ship frame).
static func bearing_deg(local: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(local.x, -local.z)), 360.0)


## Elevation -90..+90 above the deck plane (ship frame).
static func elevation_deg(local: Vector3) -> float:
	return rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length()))


## Clock position 1..12 in the deck plane: 12 bow, 3 starboard, 6 stern, 9 port
## (FT-SPA-004). Each hour covers 30°, centred on it.
static func clock(local: Vector3) -> int:
	var c: int = roundi(bearing_deg(local) / 30.0) % 12
	return 12 if c == 0 else c


## The unit vector in the ship frame (-Z bow, +X starboard, +Y up) a clock position (1 to 12)
## and a height (-2 to 2, as HEIGHT_DEG) point along: the inverse of clock and height_word.
static func direction(clock_pos: int, height: int) -> Vector3:
	var bearing: float = deg_to_rad(30.0 * (clock_pos % 12))
	var elevation: float = deg_to_rad(HEIGHT_DEG[clampi(height, -2, 2) + 2])
	return Vector3(sin(bearing) * cos(elevation), sin(elevation), -cos(bearing) * cos(elevation))


## level within ±15°, high/low to ±60°, overhead/under beyond (FT-SPA-004). Exactly 15°
## is still level and exactly 60° still high/low.
static func height_word(local: Vector3) -> String:
	var el: float = elevation_deg(local)
	if el > POLE_DEG:
		return "overhead"
	if el < -POLE_DEG:
		return "under"
	if el > LEVEL_DEG:
		return "high"
	if el < -LEVEL_DEG:
		return "low"
	return "level"


## "4 high", or only "overhead"/"under" beyond ±60°, where the clock is dropped
## (FT-SPA-003). Ship frame (FT-SPA-026).
static func clock_height(local: Vector3) -> String:
	var h: String = height_word(local)
	if h == "overhead" or h == "under":
		return h
	return "%d %s" % [clock(local), h]


## close < 1 km, mid 1-10 km, far > 10 km (FT-SPA-003): 1 km and 10 km are mid.
static func range_band(dist: float) -> String:
	if dist < CLOSE_DISTANCE:
		return "close"
	if dist <= FAR_DISTANCE:
		return "mid"
	return "far"


## "Bravo, 12 high, 3 km": a point away from the speaker's ship said relative to a named
## mark or site (FT-SPA-006, FT-SPA-026, D124). `from_ref` is the point's offset from the
## reference in the SPEAKER's ship frame, so the clock and height words are ship frame
## like every other callout; a point over a pole says only overhead or under.
static func relative(ref_name: String, from_ref: Vector3) -> String:
	return "%s, %s, %s" % [ref_name, clock_height(from_ref), distance_text(from_ref.length())]


## A distance for speech: whole metres to the nearest 100 under 1 km, one decimal of a
## kilometre to 10 km (dropped when it is whole), whole kilometres beyond.
static func distance_text(dist: float) -> String:
	if dist < CLOSE_DISTANCE:
		return "%d m" % (roundi(dist / 100.0) * 100)
	if dist < FAR_DISTANCE:
		var km: float = snappedf(dist / 1000.0, 0.1)
		return "%d km" % int(km) if is_equal_approx(km, floorf(km)) else "%.1f km" % km
	return "%d km" % roundi(dist / 1000.0)
