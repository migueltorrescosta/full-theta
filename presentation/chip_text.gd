class_name ChipText
extends RefCounted
## Chip and hover text (spec §6.1, D45, D114): `H2 · 4 high · mid`, composed from
## Callout.clock_height and Callout.range_band (shared/, FT-ARC-021): the range band
## only, never the exact range (D114); the clock dropped above ±60° (FT-SPA-003);
## bearing and mark only on hover (FT-SPA-005). Words go through I18n keys
## ("callout.<word>", "callout.precise").

const SEP: String = " · "


## "H2 · 4 high · mid" for an item at `local` (ship frame, m).
static func chip(label: String, local: Vector3) -> String:
	# clock_height is "4 high" or a lone "overhead"/"under": translate its word.
	var words: PackedStringArray = Callout.clock_height(local).split(" ")
	words[-1] = _tr("callout." + words[-1])
	var band: String = _tr("callout." + Callout.range_band(local.length()))
	return SEP.join([label, " ".join(words), band])


## "Bravo, 12 high, 3 km": a far point said relative to a mark or site, in the session
## language (Callout.relative; `from_ref` is its offset from the reference in the ship
## frame, FT-SPA-006, FT-SPA-026).
static func relative(ref_name: String, from_ref: Vector3) -> String:
	var words: PackedStringArray = Callout.clock_height(from_ref).split(" ")
	words[-1] = _tr("callout." + words[-1])
	return ", ".join([ref_name, " ".join(words), Callout.distance_text(from_ref.length())])


## "brg 123 · mk +12" for hover (FT-SPA-005).
static func precise(local: Vector3) -> String:
	var bearing: int = roundi(Callout.bearing_deg(local)) % 360
	var mark: int = roundi(Callout.elevation_deg(local))
	return _tr("callout.precise") % ["%03d" % bearing, "%+d" % mark]


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
