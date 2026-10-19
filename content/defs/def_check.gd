class_name DefCheck
extends RefCounted
## Range checks shared by the definitions' validate() methods (FT-DAT-002). Each
## appends "field: problem" to errors when the check fails.


static func id(errors: Array[String], field: String, value: StringName) -> void:
	if String(value).strip_edges().is_empty():
		errors.append("%s: must not be empty" % field)


static func positive(errors: Array[String], field: String, value: float) -> void:
	if not value > 0.0:
		errors.append("%s: must be > 0, got %s" % [field, value])


static func non_negative(errors: Array[String], field: String, value: float) -> void:
	if not value >= 0.0:
		errors.append("%s: must be >= 0, got %s" % [field, value])


## Inclusive range [lo, hi].
static func in_range(
	errors: Array[String], field: String, value: float, lo: float, hi: float
) -> void:
	if not (value >= lo and value <= hi):
		errors.append("%s: must be in [%s, %s], got %s" % [field, lo, hi, value])


## Open-low range (lo, hi], for fractions and angles that must not be zero.
static func in_range_open_low(
	errors: Array[String], field: String, value: float, lo: float, hi: float
) -> void:
	if not (value > lo and value <= hi):
		errors.append("%s: must be in (%s, %s], got %s" % [field, lo, hi, value])


static func positive_vector(errors: Array[String], field: String, value: Vector3) -> void:
	if not (value.x > 0.0 and value.y > 0.0 and value.z > 0.0):
		errors.append("%s: every component must be > 0, got %s" % [field, value])


static func unit_vector(errors: Array[String], field: String, value: Vector3) -> void:
	if absf(value.length() - 1.0) > 1e-3:
		errors.append("%s: must be a unit vector, got %s" % [field, value])


## Returns false (and records the error) when a required reference is null.
static func required(errors: Array[String], field: String, value: Object) -> bool:
	if value == null:
		errors.append("%s: required reference is missing" % field)
		return false
	return true
