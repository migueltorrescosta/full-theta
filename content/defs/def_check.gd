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


## A piecewise-linear curve: at least 2 points, x strictly ascending from 0 (to x_end
## when given), y in [0, y_max].
static func curve(
	errors: Array[String],
	field: String,
	points: PackedVector2Array,
	y_max: float,
	x_end: float = NAN
) -> void:
	var n: int = points.size()
	if n < 2:
		errors.append("%s: needs at least 2 points, got %d" % [field, n])
		return
	if is_nan(x_end):
		if points[0].x != 0.0:
			errors.append("%s: x must start at 0" % field)
	elif points[0].x != 0.0 or points[n - 1].x != x_end:
		errors.append("%s: x must run from 0 to %s" % [field, _num(x_end)])
	for i: int in n:
		var p: Vector2 = points[i]
		if i > 0 and not p.x > points[i - 1].x:
			errors.append("%s: x must be strictly ascending at point %d" % [field, i])
		if not (p.y >= 0.0 and p.y <= y_max):
			errors.append("%s: y must be in [0, %s] at point %d" % [field, _num(y_max), i])


## A whole number without its ".0", for messages.
static func _num(v: float) -> String:
	return str(int(v)) if is_finite(v) and v == roundf(v) else str(v)


## Returns false (and records the error) when a required reference is null.
static func required(errors: Array[String], field: String, value: Object) -> bool:
	if value == null:
		errors.append("%s: required reference is missing" % field)
		return false
	return true
