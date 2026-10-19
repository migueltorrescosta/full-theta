extends SceneTree
## S6 benchmark (R6): times sim ticks with 100 ships and 500 projectiles.
## Run: taskset -c 0 godot --headless --path . -s res://spikes/s6/bench.gd \
##   -- [packed|object] [ticks] [seed] [ships] [projectiles]

const WARMUP: int = 600


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var layout: String = args[0] if args.size() > 0 else "packed"
	var ticks: int = int(args[1]) if args.size() > 1 else 3600
	var seed_value: int = int(args[2]) if args.size() > 2 else 6
	var n_ships: int = int(args[3]) if args.size() > 3 else 100
	var n_proj: int = int(args[4]) if args.size() > 4 else 500
	var world: RefCounted
	if layout == "object":
		world = S6WorldObject.new(seed_value)
	else:
		world = S6WorldPacked.new(seed_value)
	world.call("setup_benchmark", n_ships, n_proj)
	for i in WARMUP:
		world.call("step")
	var times := PackedFloat64Array()
	times.resize(ticks)
	var hits_before: int = world.get("total_hits")
	for i in ticks:
		var t0 := Time.get_ticks_usec()
		world.call("step")
		times[i] = float(Time.get_ticks_usec() - t0) / 1000.0
	var hits: int = world.get("total_hits") - hits_before
	var total: float = 0.0
	for t in times:
		total += t
	times.sort()
	print(
		(
			(
				"%s seed=%d ships=%d proj=%d ticks=%d mean=%.3f p50=%.3f p99=%.3f max=%.3f ms"
				+ " hits=%d contacts=%d sum=%.6f"
			)
			% [
				layout,
				seed_value,
				n_ships,
				n_proj,
				ticks,
				total / ticks,
				times[ticks / 2],
				times[int(ticks * 0.99)],
				times[ticks - 1],
				hits,
				world.get("total_contacts"),
				world.call("checksum"),
			]
		)
	)
	quit()
