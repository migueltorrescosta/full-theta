class_name PairDef
extends Resource
## A cooperation pair of functional stations (spec §7.3, §7.4) and its balance values.
## Units are SI (FT-SIM-033, FT-DAT-013).

## Unique among pairs, the §7.3 number in lower case (dimensionless id, e.g. p1).
@export var id: StringName = &""
## Name shown to players and in reports, e.g. "Engineering + Helm".
@export var display_name: String = ""
## Least gain by which the co-op variant must beat the solo variant on each of the
## pair test's metrics (dimensionless, in (0, 1]; FT-PAIR-015 starts pairs at 0.25,
## P1 is 0.2, D121): (solo - co-op) / solo for a lower-is-better metric such as time,
## co-op / solo - 1 for a higher-is-better one (PairHarness.gain).
@export var pair_min_gain: float = 0.0
## The two crew stations of the pair (ids of StationViews.CREW), never the Captain
## (FT-PAIR-001, FT-PAIR-002), in the order of the display name.
@export var stations: Array[StringName] = []


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.in_range_open_low(errors, "pair_min_gain", pair_min_gain, 0.0, 1.0)
	if stations.size() != 2 or stations[0] == stations[1]:
		errors.append("stations: needs two different stations, got %s" % [stations])
	return errors
