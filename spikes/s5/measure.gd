extends SceneTree
## Prints the S5 scenario numbers for docs/spikes/S5.md:
##   godot --headless --path . -s res://spikes/s5/measure.gd


func _init() -> void:
	for c: Array in S5Scenarios.intercept_cases():
		var r: Dictionary = S5Scenarios.intercept(c[1], c[2])
		print(
			(
				"intercept %s: captured=%s t=%.2f s start=%.0f m end=%.0f m rel=%.0f m/s prop=%.1f kg"
				% [
					c[0],
					r.captured,
					r.time,
					r.start_distance,
					r.distance,
					r.relative_speed,
					r.propellant
				]
			)
		)
	var s: Dictionary = S5Scenarios.stop_then_approach(90.0)
	print(
		(
			"all-stop: %.2f s (residual %.3f m/s, drifted %.0f m); mark %.0f m away"
			% [s.stop_time, s.stop_speed, s.stop_drift, s.mark_distance_at_start]
		)
	)
	print(
		(
			"approach: settled after %.2f s; end %.0f m, %.3f m/s, %.4f rad/s; prop %.1f kg"
			% [s.approach_settled, s.distance, s.speed, s.rate, s.propellant]
		)
	)
	# Hold-to-approach on the moving, weaving H2 from the start position.
	var world: S5World = S5World.new()
	var hold: S5HelmInput = S5HelmInput.new()
	hold.approach = true
	var target: S5Item = world.items[S5World.TARGET]
	var reached: float = -1.0
	while world.time < 120.0:
		world.step(hold)
		var gap: float = (target.position - world.ship.position).length()
		if reached < 0.0 and gap < 1000.0:
			reached = world.time
	print(
		(
			"approach H2: within 1 km at %.1f s; at 120 s %.0f m, relative %.1f m/s"
			% [
				reached,
				(target.position - world.ship.position).length(),
				(target.velocity - world.ship.velocity).length(),
			]
		)
	)
	# Cost of one tick (assist + integrator), approach held so every controller runs.
	var start: int = Time.get_ticks_usec()
	for i: int in 36000:
		world.step(hold)
	print("tick cost: %.1f us" % ((Time.get_ticks_usec() - start) / 36000.0))
	quit(0)
