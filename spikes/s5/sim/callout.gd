class_name S5Callout
extends RefCounted
## Clock, height and range words in the ship frame (spec §6.1, FT-SPA-003, FT-SPA-004,
## FT-SPA-026). Inputs are local offsets: -Z bow, +X starboard, +Y up.

const LEVEL_DEG: float = 15.0
const POLE_DEG: float = 60.0


## Bearing 0-360, clockwise from the bow in the deck plane.
static func bearing_deg(local: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(local.x, -local.z)), 360.0)


## Elevation -90..+90 above the deck plane.
static func elevation_deg(local: Vector3) -> float:
	var flat: float = Vector2(local.x, local.z).length()
	return rad_to_deg(atan2(local.y, flat))


## Clock position 1-12: 12 bow, 3 starboard, 6 stern, 9 port.
static func clock(local: Vector3) -> int:
	var c: int = roundi(bearing_deg(local) / 30.0) % 12
	return 12 if c == 0 else c


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


## "4 high", or just "overhead"/"under" beyond 60° (FT-SPA-003).
static func clock_height(local: Vector3) -> String:
	var h: String = height_word(local)
	if h == "overhead" or h == "under":
		return h
	return "%d %s" % [clock(local), h]


static func range_band(dist: float) -> String:
	if dist < 1000.0:
		return "close"
	if dist <= 10000.0:
		return "mid"
	return "far"


static func range_text(dist: float) -> String:
	if dist < 1000.0:
		return "%d m" % roundi(dist)
	if dist < 100000.0:
		return "%.1f km" % (dist / 1000.0)
	return "%d km" % roundi(dist / 1000.0)


## Chip text, e.g. "H2 · 4 high · 2.3 km ▲closing". closing_speed > 0 means closing.
static func chip(callsign: String, local: Vector3, closing_speed: float) -> String:
	var text: String = "%s · %s · %s" % [callsign, clock_height(local), range_text(local.length())]
	if closing_speed > 1.0:
		text += " ▲closing"
	elif closing_speed < -1.0:
		text += " ▼opening"
	return text
