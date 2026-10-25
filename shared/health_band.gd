class_name HealthBand
extends RefCounted
## The four bands of a banded summary (D193, FT-PAIR-019): ok, scratched, damaged and
## critical, split at 75, 50 and 25 % of the value's maximum. Each band has a word and a
## shape so it reads without colour (FT-STN-006); the clients map them to I18n keys
## ("band.<word>") and draw the shape. Pure; the split points are data (DataTogglesDef).

enum Band { OK, SCRATCHED, DAMAGED, CRITICAL }

## The split points as shares of the maximum: below the first it is scratched or worse.
const DEFAULT_EDGES: PackedFloat64Array = [0.75, 0.5, 0.25]
const WORDS: Array[String] = ["ok", "scratched", "damaged", "critical"]
## One shape per band, drawn by the clients next to the word (never colour alone).
const SHAPES: Array[String] = ["circle", "diamond", "triangle", "square"]


## The band of a share of the maximum (0..1; clamped). A share exactly on an edge belongs to
## the better band.
static func band_of(share: float, edges: PackedFloat64Array = DEFAULT_EDGES) -> Band:
	if is_nan(share):
		return Band.CRITICAL
	if share >= edges[0]:
		return Band.OK
	if share >= edges[1]:
		return Band.SCRATCHED
	if share >= edges[2]:
		return Band.DAMAGED
	return Band.CRITICAL


## The share a band stands for on the wire: the middle of its range (the top band reaches
## 100 %, the bottom one 0 %).
static func middle(band: Band, edges: PackedFloat64Array = DEFAULT_EDGES) -> float:
	var top: float = 1.0 if band == Band.OK else edges[band - 1]
	var low: float = 0.0 if band == Band.CRITICAL else edges[band]
	return (top + low) / 2.0


## A share of the maximum, banded: the share of the band's middle.
static func quantise(share: float, edges: PackedFloat64Array = DEFAULT_EDGES) -> float:
	return middle(band_of(share, edges), edges)


static func word(band: Band) -> String:
	return WORDS[band]


static func shape(band: Band) -> String:
	return SHAPES[band]
