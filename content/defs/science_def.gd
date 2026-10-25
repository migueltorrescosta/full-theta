class_name ScienceDef
extends Resource
## Science tuning: the server-side scan noise model, the silhouette-alignment scan, the
## node-route hack and what each scan level reveals (FT-SCI-004 to FT-SCI-016, D58, D59,
## D192). One definition for the whole world, read-only at runtime (FT-ARC-020). The
## minigame numbers are tuned so a scripted average player takes 5-20 s at nominal
## noise (FT-SCI-012; tests/sim/science/test_minigame_timing.gd); the owner retunes them
## after the #13 playtest. Units are SI where a unit applies (FT-DAT-013).

## Unique among science definitions (dimensionless id).
@export var id: StringName = &""

@export_group("Noise")
## Noise of a clean scan before any term (dimensionless, 0..1).
@export var noise_base: float = 0.0
## Range at which the range term reaches 1 (m).
@export var range_ref: float = 0.0
## Weight of range / range_ref (dimensionless).
@export var range_weight: float = 0.0
## Weight of the aspect term, 0 broadside and 1 bow-on or stern-on (dimensionless).
@export var aspect_weight: float = 0.0
## Weight of 1 - sensors effectiveness (dimensionless).
@export var health_weight: float = 0.0
## Noise change per sensor pip above (less) or below (more) its nominal (dimensionless).
@export var pip_gain: float = 0.0
## Multiplier on noise with the sensors in active mode (dimensionless).
@export var active_factor: float = 0.0
## Multiplier on noise during an active ping (dimensionless).
@export var ping_factor: float = 0.0
## Multiplier on noise for a contact in probe coverage (dimensionless, P13).
@export var probe_factor: float = 0.0
## Multiplier on noise within mark_radius of the scan-position mark (dimensionless, P3).
@export var mark_factor: float = 0.0
## Distance to the scan-position mark within which mark_factor applies (m).
@export var mark_radius: float = 0.0
## Where the scan-position mark sits from the contact (m), broadside.
@export var mark_distance: float = 0.0
## Length of an active ping's low-noise window (s).
@export var ping_duration_s: float = 0.0
## Time after a ping starts before the next may start (s).
@export var ping_cooldown_s: float = 0.0
## A scan or hack reaches contacts within this share of the sensor range (dimensionless).
@export var scan_range_factor: float = 0.0
## The noise of the scripted average player's nominal case, for tests and the UI
## (dimensionless, 0..1).
@export var nominal_noise: float = 0.0

@export_group("Scan")
## Noise below which the scan has 1 rotation axis, and below which it has 2; 3 above
## (two ascending values in (0, 1), FT-SCI-014).
@export var axes_noise_steps: PackedFloat64Array = PackedFloat64Array()
## Rotation axes already aligned when the crew fully scanned the class this run
## (count, FT-SCI-015).
@export var pre_aligned_axes: int = 0
## Wireframe vertices (count).
@export var wire_vertices: int = 0
## Cloud points that are clutter at noise 1 (count); none at noise 0.
@export var clutter_max: int = 0
## Standard deviation of the cloud position error at noise 1, on a unit wireframe
## (dimensionless).
@export var sigma_max: float = 0.0
## Smallest turn about an active axis in the target pose (rad).
@export var min_angle: float = 0.0
## RMS vertex error at which the match quality is 0, on a unit wireframe (dimensionless).
@export var quality_span: float = 0.0
## Match quality at and above which the scan locks (dimensionless, 0..1, FT-SCI-016).
@export var lock_threshold: float = 0.0
## Confidence added to a locked scan (dimensionless).
@export var lock_bonus: float = 0.0
## Share of the confidence lost at noise 1 (dimensionless).
@export var noise_penalty: float = 0.0
## Scan confidence at and above which the class counts as fully scanned (dimensionless,
## FT-SCI-015).
@export var full_scan_conf: float = 0.0
## Time the scan stays open before it fails (s).
@export var scan_cap_s: float = 0.0
## Time the own-ship scan takes (s, FT-SCI-009).
@export var self_scan_s: float = 0.0

@export_group("Reveals")
## Scan confidence that reveals the class (dimensionless, 0..1).
@export var reveal_class: float = 0.0
## Scan confidence that reveals the identity (dimensionless, 0..1).
@export var reveal_identity: float = 0.0
## Scan confidence that reveals the intent (dimensionless, 0..1).
@export var reveal_intent: float = 0.0
## Scan confidence that reveals the weak points (dimensionless, 0..1).
@export var reveal_weak_points: float = 0.0
## Scan confidence that reveals the resistances (dimensionless, 0..1).
@export var reveal_resistances: float = 0.0
## Scan confidence at which a hack may start (dimensionless, 0..1).
@export var reveal_hack: float = 0.0

@export_group("Hack")
## Node grid columns (count); the entry is in the first, the subsystem in the last.
@export var hack_cols: int = 0
## Node grid rows (count).
@export var hack_rows: int = 0
## Chance of each edge beyond the guaranteed route (dimensionless).
@export var edge_density: float = 0.0
## Share of the inner nodes that start hidden (dimensionless).
@export var hidden_fraction: float = 0.0
## Share of the hidden nodes a probe-covered contact reveals (dimensionless).
@export var probe_reveal: float = 0.0
## Trace bar rise per second (1/s).
@export var trace_rate: float = 0.0
## Trace bar rise per move (dimensionless).
@export var trace_per_move: float = 0.0
## Extra trace speed at noise 1, as a share of trace_rate (dimensionless).
@export var trace_noise_gain: float = 0.0
## Multiplier on the trace speed in probe coverage (dimensionless, P13).
@export var probe_trace_factor: float = 0.0
## Effect of a successful hack by subsystem kind.
@export var effects: Array[HackEffectDef] = []


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.in_range(errors, "noise_base", noise_base, 0.0, 1.0)
	DefCheck.positive(errors, "range_ref", range_ref)
	DefCheck.non_negative(errors, "range_weight", range_weight)
	DefCheck.non_negative(errors, "aspect_weight", aspect_weight)
	DefCheck.non_negative(errors, "health_weight", health_weight)
	DefCheck.in_range(errors, "pip_gain", pip_gain, 0.0, 0.3)
	DefCheck.in_range_open_low(errors, "active_factor", active_factor, 0.0, 1.0)
	DefCheck.in_range_open_low(errors, "ping_factor", ping_factor, 0.0, 1.0)
	DefCheck.in_range_open_low(errors, "probe_factor", probe_factor, 0.0, 1.0)
	DefCheck.in_range_open_low(errors, "mark_factor", mark_factor, 0.0, 1.0)
	DefCheck.positive(errors, "mark_radius", mark_radius)
	DefCheck.positive(errors, "mark_distance", mark_distance)
	DefCheck.positive(errors, "ping_duration_s", ping_duration_s)
	DefCheck.non_negative(errors, "ping_cooldown_s", ping_cooldown_s)
	DefCheck.in_range_open_low(errors, "scan_range_factor", scan_range_factor, 0.0, 4.0)
	DefCheck.in_range(errors, "nominal_noise", nominal_noise, 0.0, 1.0)
	_validate_scan(errors)
	_validate_reveals(errors)
	_validate_hack(errors)
	return errors


## The effect for a subsystem kind, or null.
func effect_for(kind: int) -> HackEffectDef:
	for e: HackEffectDef in effects:
		if e != null and e.subsystem_kind == kind:
			return e
	return null


func _validate_scan(errors: Array[String]) -> void:
	var steps: PackedFloat64Array = axes_noise_steps
	if steps.size() != 2 or not (0.0 < steps[0] and steps[0] < steps[1] and steps[1] < 1.0):
		errors.append("axes_noise_steps: needs two ascending values in (0, 1)")
	DefCheck.in_range(errors, "pre_aligned_axes", pre_aligned_axes, 0, 2)
	DefCheck.in_range(errors, "wire_vertices", wire_vertices, 4, 24)
	DefCheck.in_range(errors, "clutter_max", clutter_max, 0, 100)
	DefCheck.non_negative(errors, "sigma_max", sigma_max)
	DefCheck.in_range(errors, "min_angle", min_angle, 0.0, PI)
	DefCheck.positive(errors, "quality_span", quality_span)
	DefCheck.in_range_open_low(errors, "lock_threshold", lock_threshold, 0.0, 1.0)
	DefCheck.in_range(errors, "lock_bonus", lock_bonus, 0.0, 1.0)
	DefCheck.in_range(errors, "noise_penalty", noise_penalty, 0.0, 1.0)
	DefCheck.in_range_open_low(errors, "full_scan_conf", full_scan_conf, 0.0, 1.0)
	DefCheck.positive(errors, "scan_cap_s", scan_cap_s)
	DefCheck.positive(errors, "self_scan_s", self_scan_s)


func _validate_reveals(errors: Array[String]) -> void:
	var ascending: Dictionary[String, float] = {
		"reveal_class": reveal_class,
		"reveal_identity": reveal_identity,
		"reveal_intent": reveal_intent,
		"reveal_weak_points": reveal_weak_points,
		"reveal_resistances": reveal_resistances,
	}
	var last: float = 0.0
	for f: String in ascending:
		var v: float = ascending[f]
		DefCheck.in_range_open_low(errors, f, v, 0.0, 1.0)
		if v < last:
			errors.append("%s: must not be below the reveal before it (%s)" % [f, last])
		last = v
	DefCheck.in_range_open_low(errors, "reveal_hack", reveal_hack, 0.0, 1.0)


func _validate_hack(errors: Array[String]) -> void:
	DefCheck.in_range(errors, "hack_cols", hack_cols, 3, 6)
	DefCheck.in_range(errors, "hack_rows", hack_rows, 2, 5)
	DefCheck.in_range(errors, "edge_density", edge_density, 0.0, 1.0)
	DefCheck.in_range(errors, "hidden_fraction", hidden_fraction, 0.0, 1.0)
	DefCheck.in_range(errors, "probe_reveal", probe_reveal, 0.0, 1.0)
	DefCheck.positive(errors, "trace_rate", trace_rate)
	DefCheck.non_negative(errors, "trace_per_move", trace_per_move)
	DefCheck.non_negative(errors, "trace_noise_gain", trace_noise_gain)
	DefCheck.in_range_open_low(errors, "probe_trace_factor", probe_trace_factor, 0.0, 1.0)
	var kinds: Dictionary[int, bool] = {}
	for i: int in effects.size():
		var e: HackEffectDef = effects[i]
		if not DefCheck.required(errors, "effects[%d]" % i, e):
			continue
		if kinds.has(e.subsystem_kind):
			errors.append("effects[%d].subsystem_kind: duplicate kind %d" % [i, e.subsystem_kind])
		kinds[e.subsystem_kind] = true
