extends SceneTree
## R16 comparison: the S6Intercept scenario at the origin, site-local at a
## site 1e8 m away, and with naive global float32 positions 1e8 m away.
## Run: godot --headless --path . -s res://spikes/s6/precision.gd


func _initialize() -> void:
	var ref := S6Intercept.run(0, Vector3.ZERO)
	var local := S6Intercept.run(1, Vector3.ZERO)
	_report("origin", ref, ref, Vector3.ZERO)
	_report("site-local, site 1e8 m away", local, ref, Vector3.ZERO)
	var bases: Array[Vector3] = [
		Vector3(2.0e4, 0.0, 0.0),
		Vector3(2.0e5, 0.0, 0.0),
		Vector3(1.0e6, 0.0, 0.0),
		Vector3(1.0e7, 0.0, 0.0),
		Vector3(1.0e8, 0.0, 0.0),
		Vector3(1.0e8, 1.0e8, 1.0e8) / sqrt(3.0),
	]
	for base in bases:
		_report("naive global float32 at %s" % base, S6Intercept.run(0, base), ref, base)
	quit()


func _report(label: String, out: Dictionary, ref: Dictionary, base: Vector3) -> void:
	var a: Array[Vector3] = out["pos"]
	var b: Array[Vector3] = ref["pos"]
	var moved: Array[float] = []
	for s in a.size():
		moved.append((float(a[s].x) - float(base.x)) - b[s].x)
	print(
		(
			"%s: hit tick %d (ship %d), warning tick %d, contact tick %d, max pos error %.3f m, x err %s"
			% [
				label,
				out["hit_tick"],
				out["hit_ship"],
				out["warn_tick"],
				out["contact_tick"],
				S6Intercept.max_error(out, ref, base),
				moved,
			]
		)
	)
