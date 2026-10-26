class_name ViewFilter
extends RefCounted
## What one snapshot view may carry of other stations' data (FT-NET-009, FT-PAIR-005,
## FT-PAIR-007 to FT-PAIR-010, FT-PAIR-014, FT-PAIR-019, FT-JNT-005): the entry's stations
## against the session's DataToggles. A field of another station's data reaches the view
## only through a toggle:
## - a summary (the top bar's shields and reactor, Helm's thrust envelope and shield ring,
##   propellant, the probe stock and fabrication timer) is exact, banded to the four bands of
##   D193 or absent, by the summaries toggle;
## - a shortcut (routes on Helm, weak points and track feeds on Weapons, diagnosed causes and
##   hazard countdowns on Engineering) is delivered when its toggle is on and its source
##   station has shared it (D210; the code's "#a,b" suffix names the shared ones);
## - a joint view that holds the source station sees it as if the toggle were on;
## - the Captain and the Viewer are no station of the pairs and see everything;
## - Engineering's data never reaches a view holding Comms but not Engineering, at any
##   difficulty: its summaries are absent and the hull is the band (FT-PAIR-010, D68).
## Game rules never read a filter: it only decides what a snapshot says (FT-PAIR-014).
## Absent values are neutral numbers (0, or 1 for an envelope scale); the clients read the
## toggle code from the `lobby` event to draw an em dash instead (StationContext).

## Feature ids for grants(): the SHORTCUT toggles of content/toggles/toggles.tres.
const ROUTES: StringName = &"routes"
const WEAK_POINTS: StringName = &"weak_points"
const TRACK_FEEDS: StringName = &"track_feeds"
const DIAGNOSED_CAUSES: StringName = &"diagnosed_causes"
const HAZARD_COUNTDOWNS: StringName = &"hazard_countdowns"
const CHIPS: StringName = &"chips"
const CONTRACT_FLAGS: StringName = &"contract_flags"
const VERIFY_CHIP: StringName = &"verify_chip"
const LANES: StringName = &"lanes"
const MISSION_ICON: StringName = &"mission_icon"

## Owners of the summarised fields.
const ENG: Array = ["engineering"]
const HELM: Array = ["helm"]
const HELM_ENG: Array = ["helm", "engineering"]
const RELAY_OWNER: Array = ["relay"]
## The fabrication timer is Engineering's build shown on Relay's screen.
const RELAY_ENG: Array = ["relay", "engineering"]

var entry: String = ""
var toggles: DataToggles
var stations: Array[String] = []
## The shortcuts the source stations shared and that haven't expired (feature -> true).
var shared: Dictionary = {}
## Captain, Viewer: no filtering.
var sees_all: bool = false
## A Comms view without Engineering: no Engineering data, hull as a band.
var condition_hidden: bool = false


## A toggle code with the shared shortcuts appended: "<code>#a,b" (just the code for none).
static func code_with(code: String, shared_features: Array) -> String:
	if shared_features.is_empty():
		return code
	var names: Array[String] = []
	for id: Variant in shared_features:
		names.append(String(id))
	names.sort()
	return code + "#" + ",".join(names)


## The filter of an entry at a toggle code (DataToggles code, optionally with the shared
## shortcuts after a "#", code_with()); null when the code is malformed.
static func of(entry_id: String, code: String) -> ViewFilter:
	var parts: PackedStringArray = code.split("#", true, 1)
	var picked: DataToggles = DataToggles.parse(parts[0])
	if picked == null:
		return null
	var f: ViewFilter = ViewFilter.new()
	if parts.size() > 1:
		for id: String in parts[1].split(",", false):
			f.shared[StringName(id)] = true
	f.entry = entry_id
	f.toggles = picked
	f.stations = StationViews.stations_of(entry_id)
	f.sees_all = f.stations.is_empty()
	f.condition_hidden = f.stations.has("comms") and not f.stations.has("engineering")
	return f


## Whether a shortcut reaches the view: the view holds the source station (FT-JNT-005, no
## press needed), or its toggle is on and the source shared it (D210).
func grants(feature: StringName) -> bool:
	if sees_all:
		return true
	var def: DataToggleDef = DataToggles.toggle_def(feature)
	if def != null and def.source != &"":
		if stations.has(String(def.source)):
			return true
		return toggles.on(feature) and shared.has(feature)
	return toggles.on(feature)


## How an owner's summary reaches the view: 2 exact, 1 banded, 0 absent. The owners are the
## stations whose data it is; a view holding one of them sees it exactly.
func summary_mode(owners: Array) -> int:
	if sees_all:
		return 2
	for o: String in owners:
		if stations.has(o):
			return 2
	if condition_hidden and owners.has("engineering"):
		return 0
	return toggles.summaries()


## A summarised number: exact, the middle of its D193 band (against `maximum`), or `absent`.
func summarise(value: float, maximum: float, owners: Array, absent: float = 0.0) -> float:
	match summary_mode(owners):
		2:
			return value
		1:
			if not maximum > 0.0:
				return absent
			var share: float = clampf(value / maximum, 0.0, 1.0)
			return HealthBand.quantise(share, DataToggles.def().band_edges) * maximum
	return absent


## The hull: exact, except that a view holding Comms but not Engineering sees its band at
## every difficulty (FT-PAIR-010).
func hull(value: float, maximum: float) -> float:
	if not condition_hidden or not maximum > 0.0:
		return value
	var share: float = clampf(value / maximum, 0.0, 1.0)
	return HealthBand.quantise(share, DataToggles.def().band_edges) * maximum


## Applies the filter to a block's values (StationViews.block_bytes), changing the fields
## that are other stations' data.
func apply(kind: int, values: Dictionary, world: SimWorld, ship: int) -> void:
	if sees_all:
		return
	var def: ShipDef = world.defs[ship]
	match kind:
		StationViews.Section.STATUS:
			values["hull"] = hull(values["hull"], def.hull_max)
			values["shields"] = summarise(values["shields"], def.shields.max_strength, ENG)
			values["pips_used"] = summarise(values["pips_used"], def.power.reactor_pips, ENG)
			values["propellant"] = summarise(
				values["propellant"], def.propellant_capacity, HELM_ENG
			)
		StationViews.Section.HELM:
			values["shield_tightness"] = summarise(
				values["shield_tightness"], def.shields.tightness_max, ENG
			)
			values["shield_power"] = summarise(values["shield_power"], 1.0, ENG)
			values["thrust_scale"] = summarise(values["thrust_scale"], 1.0, ENG, 1.0)
			values["torque_scale"] = summarise(values["torque_scale"], 1.0, ENG, 1.0)
		StationViews.Section.ENGINEERING:
			# Helm's shield focus is a direction: shown, or not (a banded direction is
			# no direction).
			if summary_mode(HELM) == 0:
				values["shield_focus"] = Vector3.ZERO
			if not grants(DIAGNOSED_CAUSES):
				for row: Dictionary in values["subsystems"]:
					row["fault_cause"] = 0
		StationViews.Section.RELAY:
			var mode: int = summary_mode(RELAY_OWNER)
			if mode < 2:
				values["stock"] = summarise(values["stock"], def.probes, RELAY_OWNER)
			if mode == 0:
				values["probes"] = []
				values["lanes"] = false
			values["fab_left"] = summarise(values["fab_left"], def.probe_fab_s, RELAY_ENG)
			# The hazards Relay knows reach another station through the countdown toggle.
			if not (stations.has("relay") or grants(HAZARD_COUNTDOWNS)):
				values["hazards"] = []
		StationViews.Section.FEEDS:
			if not grants(WEAK_POINTS):
				values["weak"] = []
				values["windows"] = []
			if not grants(TRACK_FEEDS):
				values["tracks"] = []
			if not grants(CONTRACT_FLAGS):  # (P9, FT-MIS-042)
				values["flags"] = []


## A short string naming what the filter does to one section kind: filters that do the same
## to it share one encoded section (SnapshotBuilder).
func signature(kind: int) -> String:
	var out: String = ""
	match kind:
		StationViews.Section.STATUS:
			out = (
				"h%d.s%d.r%d"
				% [1 if condition_hidden else 0, summary_mode(ENG), summary_mode(HELM_ENG)]
			)
		StationViews.Section.HELM:
			out = "e%d" % summary_mode(ENG)
		StationViews.Section.ENGINEERING:
			out = "c%d.f%d" % [1 if grants(DIAGNOSED_CAUSES) else 0, summary_mode(HELM)]
		StationViews.Section.RELAY:
			var hazards: bool = stations.has("relay") or grants(HAZARD_COUNTDOWNS)
			out = (
				"p%dh%df%d"
				% [summary_mode(RELAY_OWNER), 1 if hazards else 0, summary_mode(RELAY_ENG)]
			)
		StationViews.Section.FEEDS:
			out = (
				"w%dt%df%d"
				% [
					1 if grants(WEAK_POINTS) else 0,
					1 if grants(TRACK_FEEDS) else 0,
					1 if grants(CONTRACT_FLAGS) else 0,
				]
			)
		StationViews.Section.CHIPS:
			out = "*" if sees_all else ",".join(stations)
		StationViews.Section.COMMS:  # the science icon on replies (P14)
			out = "v%d.m%d" % [1 if grants(VERIFY_CHIP) else 0, 1 if grants(MISSION_ICON) else 0]  # F
	return out
