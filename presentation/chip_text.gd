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
	var band: String = _tr("callout." + Callout.range_band(local.length()))
	return SEP.join([label, clock_words(local), band])


## "4 high" with its height word translated: Callout.clock_height is "4 high" or a lone
## "overhead"/"under", and only that last word goes through I18n.
static func clock_words(local: Vector3) -> String:
	var words: PackedStringArray = Callout.clock_height(local).split(" ")
	words[-1] = _tr("callout." + words[-1])
	return " ".join(words)


## "Bravo, 12 high, 3 km": a far point said relative to a mark or site, in the session
## language (Callout.relative; `from_ref` is its offset from the reference in the ship
## frame, FT-SPA-006, FT-SPA-026).
static func relative(ref_name: String, from_ref: Vector3) -> String:
	return ", ".join([ref_name, clock_words(from_ref), Callout.distance_text(from_ref.length())])


## A mark's label on the lists: its name, then ` · callsign` while it is attached to a
## contact (the same on the Relay HUD and the Relay phone).
static func mark_label(m: Dictionary, view: NetViewState) -> String:
	var text: String = str(m["name"])
	if int(m.get("contact", -1)) >= 0:
		text += SEP + view.callsign(int(m["contact"]))
	return text


## "brg 123 · mk +12" for hover (FT-SPA-005).
static func precise(local: Vector3) -> String:
	var bearing: int = roundi(Callout.bearing_deg(local)) % 360
	var mark: int = roundi(Callout.elevation_deg(local))
	return _tr("callout.precise") % ["%03d" % bearing, "%+d" % mark]


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
