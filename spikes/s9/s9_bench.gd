extends SceneTree
## S9 offline probe: runs the S6 load and the snapshot builder without sockets
## and prints mean delta and full message sizes per catalogue entry and the
## build cost, so codec settings can be compared quickly.
## godot --headless --path . -s res://spikes/s9/s9_bench.gd -- [snapshots] [pos_tol_m]
## [rot_tol_deg] [near_range_m] [proj_range_m]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var snaps: int = int(args[0]) if args.size() > 0 else 900
	var opts: Dictionary = {
		"pos_tol": float(args[1]) if args.size() > 1 else 0.5,
		"rot_tol_deg": float(args[2]) if args.size() > 2 else 1.0,
		"near_range": float(args[3]) if args.size() > 3 else 2000.0,
		"proj_range": float(args[4]) if args.size() > 4 else 1000.0,
	}
	var world: S9World = S9World.new(1)
	world.setup_benchmark(100, 500)
	var b: S9Builder = S9Builder.new(world, opts)
	var entries: Array = S9Views.SECTIONS.keys()
	var sums: Dictionary = {}
	var fulls: Dictionary = {}
	for e: String in entries:
		sums[e] = 0
		fulls[e] = 0
	var build_us: int = 0
	var warm: int = 60
	var parts: Dictionary = {}
	for snap: int in range(1, snaps + warm + 1):
		world.step()
		b.note_tick_events()
		world.step()
		b.note_tick_events()
		var t0: int = Time.get_ticks_usec()
		b.build(snap, 0)
		for s: int in range(6):
			for e: String in entries:
				var m: PackedByteArray = b.message(s, e, "normal", false)
				if snap > warm:
					sums[e] += m.size()
		if snap > warm:
			build_us += Time.get_ticks_usec() - t0
		else:
			b.take_counts()
		if snap == snaps + warm:
			for e: String in entries:
				fulls[e] = b.message(0, e, "normal", true).size()
	parts = b.take_counts()
	for k: String in parts:
		if k.begins_with("us_"):
			parts[k] = snprintf_ms(parts[k], snaps)
	var out: Array[String] = []
	for e: String in entries:
		out.append("%s %.0f/%d" % [e, sums[e] / float(snaps * 6), fulls[e]])
	print(
		(
			"opts=%s delta/full bytes: %s; build+42 messages %.3f ms per snapshot; %s"
			% [JSON.stringify(opts), ", ".join(out), build_us / 1000.0 / snaps, parts]
		)
	)
	quit()


static func snprintf_ms(total_us: int, n: int) -> String:
	return "%.3f ms" % (total_us / 1000.0 / n)
