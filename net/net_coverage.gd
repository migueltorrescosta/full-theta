class_name NetCoverage
extends RefCounted
## The coverage check of one ship (FT-NET-019, FT-NET-020, FT-GEN-004, FT-GEN-005,
## D66, D67): at least min_crew crew players, and each of the six functional stations
## covered by at least one crew pick. Captain and Viewer picks don't count. Pure: the
## caller passes the catalogue entries its crew hold (ServerSession counts the sessions
## connected or within their grace period).

## Crew players a ship needs (D66); --dev-all-stations lowers it to 1 (FT-NET-029).
const MIN_CREW: int = 3


## The functional stations no entry covers, in StationViews.CREW order.
static func uncovered(entries: Array) -> Array[String]:
	var covered: Dictionary = {}
	for entry: String in entries:
		for station: String in StationViews.stations_of(entry):
			covered[station] = true
	var out: Array[String] = []
	for station: String in StationViews.CREW:
		if not covered.has(station):
			out.append(station)
	return out


## Crew players among the entries: those holding a functional station.
static func crew_count(entries: Array) -> int:
	var n: int = 0
	for entry: String in entries:
		if StationViews.is_crew(entry):
			n += 1
	return n


static func passes(entries: Array, min_crew: int = MIN_CREW) -> bool:
	return crew_count(entries) >= min_crew and uncovered(entries).is_empty()
