extends SceneTree
## Sim-only cost of the load gate's world (#11, D160): builds a LoadEncounter and steps it
## with SimWorld.step's phases timed one by one, plus a SimCopy.capture every second tick
## (what NetServer does). No sockets. Prints per-phase means and the tick mean, p50, p99
## and max (ms) every --every ticks and at the end.
##
## taskset -c 0,1 godot --headless --path . -s res://tools/l4/sim_profile.gd --
##   [--world 12] [--crew 6] [--ticks 3600] [--every 600] [--seed 1] [--neutral]
## --world is the total ship count (6 crew + raiders); --neutral leaves the crew alone.
## At the end it prints the state hash and a hash of every event: an optimisation that
## keeps behaviour keeps both for the same arguments.

const PHASES: Array[String] = [
	"apply",
	"knowledge",
	"ai",
	"power",
	"assist",
	"integrate",
	"weapons",
	"collision",
	"hits",
	"shields",
	"damage",
	"outcome"
]

var _opt: Dictionary = {
	"world": 12, "crew": 6, "ticks": 3600, "every": 600, "seed": 1, "neutral": false
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var key: String = args[i].trim_prefix("--")
		if key == "neutral":
			_opt["neutral"] = true
		elif _opt.has(key) and i + 1 < args.size() and args[i + 1].is_valid_int():
			_opt[key] = args[i + 1].to_int()
			i += 1
		else:
			push_error("sim_profile: bad argument %s" % args[i])
			quit(2)
			return
		i += 1
	var defs: DefLibrary = DefLibrary.new()
	var enc: LoadEncounter = LoadEncounter.new(
		_opt["seed"],
		"profile",
		defs.ship(&"m1_corvette"),
		defs.enemy(&"m1_raider"),
		_opt["crew"],
		_opt["world"],
		not _opt["neutral"]
	)
	var w: SimWorld = enc.build()
	if w == null:
		push_error("sim_profile: %s" % [enc.validate()])
		quit(2)
		return
	print(
		(
			"sim_profile: %d ships (%d crew), %d ticks, load %s"
			% [_opt["world"], _opt["crew"], _opt["ticks"], _loadavg()]
		)
	)
	var acc: PackedFloat64Array = PackedFloat64Array()
	acc.resize(PHASES.size() + 1)
	var ticks: PackedInt64Array = PackedInt64Array()
	var from: int = 0
	var events: HashingContext = HashingContext.new()
	events.start(HashingContext.HASH_SHA256)
	for n: int in _opt["ticks"]:
		var t: PackedInt64Array = PackedInt64Array([Time.get_ticks_usec()])
		w.call("_apply_commands")
		t.append(Time.get_ticks_usec())
		KnowledgeSystem.step(w)
		t.append(Time.get_ticks_usec())
		EnemyAi.step(w)
		t.append(Time.get_ticks_usec())
		PowerSystem.step(w)
		t.append(Time.get_ticks_usec())
		AssistSystem.step(w)
		t.append(Time.get_ticks_usec())
		Integrator.step_all(w.kin, SimWorld.DT)
		t.append(Time.get_ticks_usec())
		WeaponSystem.step(w)
		t.append(Time.get_ticks_usec())
		CollisionSystem.step(w)
		t.append(Time.get_ticks_usec())
		HitResolver.resolve(w)
		t.append(Time.get_ticks_usec())
		ShieldSystem.step(w)
		t.append(Time.get_ticks_usec())
		DamageSystem.step(w)
		t.append(Time.get_ticks_usec())
		OutcomeSystem.step(w)
		t.append(Time.get_ticks_usec())
		w.tick += 1
		var drained: Array[SimEvent] = w.drain_events()
		if n % 2 == 0:
			SimCopy.capture(w)
		t.append(Time.get_ticks_usec())
		for k: int in PHASES.size() + 1:
			acc[k] += t[k + 1] - t[k]
		ticks.append(t[PHASES.size()] - t[0])
		if (n + 1) % _opt["every"] == 0 or n + 1 == _opt["ticks"]:
			_report(w, n + 1, ticks.slice(from), acc)
			from = n + 1
			acc.fill(0.0)
		for e: SimEvent in drained:
			events.update(
				var_to_bytes(
					[e.tick, e.kind, e.ship_id, e.faction, e.other_id, e.value, e.vector, e.tag]
				)
			)
	print("state hash %s events hash %s" % [w.state_hash(), events.finish().hex_encode()])
	quit(0)


func _report(w: SimWorld, at: int, ticks: PackedInt64Array, acc: PackedFloat64Array) -> void:
	var n: int = ticks.size()
	ticks.sort()
	var total: float = 0.0
	for x: int in ticks:
		total += x
	var alive: int = 0
	for id: int in w.ship_count():
		if w.kin.is_alive(id):
			alive += 1
	var line: String = (
		"tick %d: sim mean %.2f p50 %.2f p99 %.2f max %.2f ms; alive %d, projectiles %d; per tick:"
		% [
			at,
			total / n / 1000.0,
			ticks[n / 2] / 1000.0,
			ticks[mini(n - 1, int(n * 0.99))] / 1000.0,
			ticks[n - 1] / 1000.0,
			alive,
			w.projectiles.size()
		]
	)
	for k: int in PHASES.size():
		line += " %s %.3f" % [PHASES[k], acc[k] / n / 1000.0]
	line += "; capture (every 2nd tick) %.3f" % (acc[PHASES.size()] / n * 2.0 / 1000.0)
	print(line)


static func _loadavg() -> String:
	var f: FileAccess = FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().substr(0, 14) if f != null else "?"
