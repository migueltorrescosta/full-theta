extends SceneTree
## Net-thread snapshot build cost of the load gate's world without sockets (w-j12): builds
## a LoadEncounter with the Science definition (as the server does), steps it with the
## load clients' commands (each Helm steers every 0.5 s, each Weapons fires every second),
## and every second tick restores a SimCopy and runs
## SnapshotWriter.build for the 64 seats of LoadSeats with the load probe's part timing
## (D161), then assembles every stream key's delta message. Prints the mean ms per
## snapshot of each part, as load_check.py's "Build by part" line does, and a hash of
## every message: an optimisation that keeps the bytes keeps the hash for the same
## arguments.
##
## taskset -c 0,1 godot --headless --path . -s res://tools/l4/snapshot_profile.gd --
##   [--world 12] [--warmup 600] [--ticks 1200] [--seed 1]

var _opt: Dictionary = {"world": 12, "warmup": 600, "ticks": 1200, "seed": 1}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, args.size() - 1, 2):
		var key: String = args[i].trim_prefix("--")
		if not _opt.has(key) or not args[i + 1].is_valid_int():
			push_error("snapshot_profile: bad argument %s" % args[i])
			quit(2)
			return
		_opt[key] = args[i + 1].to_int()
	var defs: DefLibrary = DefLibrary.new()
	var enc: LoadEncounter = LoadEncounter.new(
		_opt["seed"], "profile", defs.ship(&"m1_corvette"), defs.npc(&"m1_raider"), 6, _opt["world"]
	)
	enc.science = defs.science()
	var w: SimWorld = enc.build()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _opt["seed"]
	var keys: Array = []
	for i: int in LoadSeats.CONNECTIONS:
		var s: Array = LoadSeats.seat(i)
		keys.append(StationCatalogue.key(s[0], s[1]))
	var writer: SnapshotWriter = SnapshotWriter.new()
	writer.time_parts = true
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var snaps: int = 0
	var build_us: int = 0
	for n: int in _opt["warmup"] + _opt["ticks"]:
		_commands(w, n, rng)
		w.step()
		if n % 2 == 1:
			continue
		var copy: SimWorld = SimCopy.restore(SimCopy.capture(w))
		if n == _opt["warmup"]:
			writer.part_us.fill(0)
			build_us = 0
			snaps = 0
		var t0: int = Time.get_ticks_usec()
		writer.build(copy, n / 2, keys)
		build_us += Time.get_ticks_usec() - t0
		snaps += 1
		for k: String in keys:
			hash.update(writer.message(k, false))
	var line: String = (
		"snapshot_profile: %d ships, %d snapshots, load %s; build mean %.3f ms; by part:"
		% [_opt["world"], snaps, _loadavg(), build_us / 1000.0 / snaps]
	)
	line += " near_sets %.3f" % (writer.part_us[0] / 1000.0 / snaps)
	for kind: int in StationCatalogue.Section.values():
		var part: String = StationCatalogue.Section.find_key(kind)
		line += " %s %.3f" % [part.to_lower(), writer.part_us[kind] / 1000.0 / snaps]
	print(line)
	print("messages hash %s" % hash.finish().hex_encode())
	quit(0)


## The load clients' commands (tools/l4/load_client.gd), staggered by ship.
static func _commands(w: SimWorld, n: int, rng: RandomNumberGenerator) -> void:
	for ship: int in 6:
		var c: SimCommand = null
		if n % 30 == ship:
			var rot: Vector3 = Vector3(
				rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2)
			)
			c = SimCommands.from_dict(
				{"kind": "helm_input", "throttle": rng.randf_range(0.2, 1.0), "rotation": rot}
			)
		elif n % 60 == ship + 6:
			c = SimCommands.from_dict({"kind": "fire", "mount_index": 0})
		if c != null:
			c.ship_id = ship
			w.submit(c)


static func _loadavg() -> String:
	var f: FileAccess = FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().substr(0, 14) if f != null else "?"
