class_name Callout
extends RefCounted
## Spoken spatial callouts (spec §6.1, D45, D97), shared by the sim and every client
## (FT-ARC-021): pure functions of plain values, naming nothing outside shared/.
##
## Frame rule (FT-SPA-026): the clock and the words level, high, low, overhead and under
## are always ship frame, computed from an offset in the ship's local frame (-Z bow,
## +X starboard, +Y up); `up N` / `down N` are world frame and only ever follow a grid
## square (grid_callout). No function here mixes the two vocabularies.

## Height words switch from level to high/low at this elevation (FT-SPA-004).
const LEVEL_DEG: float = 15.0
## Above this elevation only overhead/under, without a clock (FT-SPA-003, NAV-7).
const POLE_DEG: float = 60.0
## Range bands (m): close below CLOSE_M, far above FAR_M, mid in between (FT-SPA-003).
const CLOSE_M: float = 1000.0
const FAR_M: float = 10000.0
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


## Ship-frame offset of a world-frame offset, for a ship with the given orientation.
static func to_ship(world_offset: Vector3, orientation: Quaternion) -> Vector3:
	return orientation.inverse() * world_offset


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


## clock_height for a world-frame offset seen from a ship with this orientation.
static func ship_callout(world_offset: Vector3, orientation: Quaternion) -> String:
	return clock_height(to_ship(world_offset, orientation))


## close < 1 km, mid 1-10 km, far > 10 km (FT-SPA-003): 1 km and 10 km are mid.
static func range_band(dist: float) -> String:
	if dist < CLOSE_M:
		return "close"
	if dist <= FAR_M:
		return "mid"
	return "far"


## Exact range for markers and the radar: "650 m", "2.3 km", "140 km". The unit switches
## on the rounded value, so 999.7 m reads "1.0 km", never "1000 m".
static func range_text(dist: float) -> String:
	if roundi(dist) < 1000:
		return "%d m" % roundi(dist)
	if roundi(dist / 100.0) < 1000:
		return "%.1f km" % (dist / 1000.0)
	return "%d km" % roundi(dist / 1000.0)


## Chip text as spoken, "H2 · 4 high · mid ▲closing" (FT-SPA-003: a band, not a
## distance). closing_speed (m/s) > 0 means closing; within ±1 m/s no arrow.
static func chip(callsign: String, local: Vector3, closing_speed: float) -> String:
	var text: String = "%s · %s · %s" % [callsign, clock_height(local), range_band(local.length())]
	if closing_speed > 1.0:
		text += " ▲closing"
	elif closing_speed < -1.0:
		text += " ▼opening"
	return text


## Grid square of a world-frame position on the ecliptic map (FT-SPA-006): columns are
## letters along +X (A, B, ..., Z, AA, ...), rows are numbers from 1 along +Z, counted from
## the map corner `origin`, each square `square_size` m wide. "" off the map (left of or
## before the corner).
static func grid_square(world_pos: Vector3, origin: Vector3, square_size: float) -> String:
	var col: int = floori((world_pos.x - origin.x) / square_size)
	var row: int = floori((world_pos.z - origin.z) / square_size)
	if col < 0 or row < 0:
		return ""
	return _column_letters(col) + str(row + 1)


## World height in grid layers above the map plane through `origin`, rounded to the
## nearest layer: +2 is "up 2" (FT-SPA-026).
static func grid_layer(world_pos: Vector3, origin: Vector3, layer_size: float) -> int:
	return roundi((world_pos.y - origin.y) / layer_size)


## "grid D4, up 2" / "grid D4, down 1" / "grid D4" on the map plane: the only form in
## which world height is said (FT-SPA-026). "" off the map.
static func grid_callout(
	world_pos: Vector3, origin: Vector3, square_size: float, layer_size: float
) -> String:
	var square: String = grid_square(world_pos, origin, square_size)
	if square.is_empty():
		return ""
	var layer: int = grid_layer(world_pos, origin, layer_size)
	if layer > 0:
		return "grid %s, up %d" % [square, layer]
	if layer < 0:
		return "grid %s, down %d" % [square, -layer]
	return "grid " + square


## 0 -> A, 25 -> Z, 26 -> AA (spreadsheet columns).
@warning_ignore("integer_division")
static func _column_letters(col: int) -> String:
	var text: String = ""
	var n: int = col + 1
	while n > 0:
		n -= 1
		text = LETTERS[n % 26] + text
		n /= 26
	return text
