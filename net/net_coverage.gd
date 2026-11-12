class_name NetCoverage
extends RefCounted
## The coverage check of one ship (FT-NET-019, FT-NET-020, FT-GEN-004, FT-GEN-005,
## D66, D67): at least min_crew crew players, and each of the six functional stations
## covered by at least one crew pick. Captain and Viewer picks don't count. Pure: the
## caller passes the seats its crew hold (NetGame counts the sessions
## connected or within their grace period).

## Crew players a ship needs (D66); --dev-all-stations lowers it to 1 (FT-NET-029).
const MIN_CREW: int = 3


## The functional stations no seat covers, in StationCatalogue.CREW order.
static func uncovered(seats: Array) -> Array[String]:
	var covered: Dictionary = {}
	for seat: String in seats:
		for station: String in StationCatalogue.stations_of(seat):
			covered[station] = true
	var out: Array[String] = []
	for station: String in StationCatalogue.CREW:
		if not covered.has(station):
			out.append(station)
	return out


## Crew players among the seats: those holding a functional station.
static func crew_count(seats: Array) -> int:
	var n: int = 0
	for seat: String in seats:
		if StationCatalogue.is_crew(seat):
			n += 1
	return n


static func passes(seats: Array, min_crew: int = MIN_CREW) -> bool:
	return crew_count(seats) >= min_crew and uncovered(seats).is_empty()


## Whether seats that pass now would fail once `leaving` goes and `joining` (if not "")
## arrives (FT-NET-042, FT-NET-043).
static func breaks(seats: Array, min_crew: int, leaving: String, joining: String = "") -> bool:
	if not passes(seats, min_crew):
		return false
	var after: Array = seats.duplicate()
	after.erase(leaving)
	if joining != "":
		after.append(joining)
	return not passes(after, min_crew)
