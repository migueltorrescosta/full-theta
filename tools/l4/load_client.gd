extends SceneTree
## Load-gate client process (#11, FT-GEN-003, FT-NET-040, D160, D161): one Godot process
## holding several NetClients, each standing in for a remote device. Seat i of the
## 64-seat plan (LoadSeats) picks its ship and entry; each ship's Helm presses Start until
## a `started` event names that ship (every ship is started, D129); once its own ship has
## started, a Helm crew steers (helm input every 0.5 s) and a Weapons crew fires mount 0
## every second, so the command path carries load too. Every
## client logs each snapshot's seq and arrival time (NetClient.snapshot_log). When the
## server closes the connections (the probe window ended) the process writes its log
## and exits 0; 1 if a seat's pick was refused, a snapshot failed to decode or --max-s
## passed first.
##
## godot --headless --path . -s res://tools/l4/load_client.gd -- --url ws://HOST:PORT
##   --first I --count N --log PATH [--ships 6] [--max-s 300] [--no-commands]
## --full-probe instead connects one client that must be refused with session_full
## (FT-NET-014): exit 0 when it is, 1 otherwise.

const HELM_EVERY_US: int = 500_000
const FIRE_EVERY_US: int = 1_000_000
const READY_EVERY_US: int = 1_000_000
const FULL_PROBE_TIMEOUT_US: int = 20_000_000

var url: String = ""
var first: int = 0
var count: int = 8
var ships: int = 6
var log_path: String = ""
var max_s: float = 300.0
var commands: bool = true
var full_probe: bool = false

var _clients: Array[NetClient] = []
## Per client: {seat, ship, entry, picked, pick_sent, next_us, rejects, welcomed}.
var _seats: Array[Dictionary] = []
var _start_us: int = 0
## Ships a `started` event named (broadcast to every client): ship -> true.
var _started_ships: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _done: bool = false


func _initialize() -> void:
	Engine.max_fps = 250
	_start_us = Time.get_ticks_usec()
	if not _parse(OS.get_cmdline_user_args()):
		push_error("load_client: bad command line")
		quit(2)
		return
	_rng.seed = first + 1
	var n: int = 1 if full_probe else count
	for k: int in n:
		var c: NetClient = NetClient.new()
		c.name = "probe65" if full_probe else "load%02d" % (first + k)
		c.log_snapshots = not full_probe
		c.connect_to(url)
		_clients.append(c)
		var seat: Array = LoadSeats.seat(first + k, ships)
		(
			_seats
			. append(
				{
					"seat": first + k,
					"ship": seat[0],
					"entry": seat[1],
					"picked": "",
					"pick_sent": false,
					"next_us": 0,
					"rejects": {},
					"welcomed": false,
				}
			)
		)


func _process(_delta: float) -> bool:
	if _done:
		return true
	var now: int = Time.get_ticks_usec()
	if full_probe:
		return _probe_full(now)
	var open: int = 0
	for k: int in _clients.size():
		var c: NetClient = _clients[k]
		c.poll()
		var s: Dictionary = _seats[k]
		for e: Dictionary in c.take_events():
			_on_event(s, e)
		if c.is_welcomed():
			s["welcomed"] = true
			open += 1
			_drive(c, s, k, now)
		elif c.state != NetClient.State.CLOSED or not s["welcomed"]:
			open += 1
	if open == 0:
		_finish("closed by server")
	elif now - _start_us > int(max_s * 1e6):
		_finish("ran longer than --max-s")
	return _done


func _drive(c: NetClient, s: Dictionary, k: int, now: int) -> void:
	if not s["pick_sent"]:
		c.pick(s["ship"], s["entry"])
		s["pick_sent"] = true
		s["next_us"] = now + _rng.randi_range(0, HELM_EVERY_US)
		return
	if s["picked"] != "ok" or now < s["next_us"]:
		return
	if not _started_ships.has(s["ship"]):
		if LoadSeats.starts(first + k, ships):
			c.set_ready(true)
		s["next_us"] = now + READY_EVERY_US
		return
	if not commands:
		return
	match s["entry"]:
		"helm":
			var rot: Vector3 = Vector3(
				_rng.randf_range(-0.3, 0.3),
				_rng.randf_range(-0.3, 0.3),
				_rng.randf_range(-0.2, 0.2)
			)
			c.helm(_rng.randf_range(0.2, 1.0), rot)
			s["next_us"] = now + HELM_EVERY_US
		"weapons":
			c.fire(0)
			s["next_us"] = now + FIRE_EVERY_US
		_:
			s["next_us"] = now + 3_600_000_000


func _on_event(s: Dictionary, e: Dictionary) -> void:
	var p: Dictionary = e.get("payload", {})
	match String(e.get("type", "")):
		"picked":
			s["picked"] = "ok" if String(p.get("reason", "")) == "" else String(p["reason"])
		"started":
			_started_ships[int(p.get("ship", -1))] = true
		"lobby":
			if bool(p.get("started", false)):
				_started_ships[int(p.get("ship", -1))] = true
		"command_rejected", "request_rejected":
			var why: String = String(p.get("reason", "?"))
			s["rejects"][why] = int(s["rejects"].get(why, 0)) + 1


func _probe_full(now: int) -> bool:
	var c: NetClient = _clients[0]
	c.poll()
	if c.state == NetClient.State.REJECTED or c.is_welcomed():
		var ok: bool = c.state == NetClient.State.REJECTED and c.reject_reason == "session_full"
		_write({"full_probe": {"state": c.state, "reason": c.reject_reason, "ok": ok}})
		_done = true
		quit(0 if ok else 1)
	elif now - _start_us > FULL_PROBE_TIMEOUT_US:
		_write({"full_probe": {"state": c.state, "reason": "timeout", "ok": false}})
		_done = true
		quit(1)
	return _done


func _finish(why: String) -> void:
	var ok: bool = why == "closed by server"
	var out: Array = []
	for k: int in _clients.size():
		var c: NetClient = _clients[k]
		var s: Dictionary = _seats[k]
		ok = ok and s["picked"] == "ok" and int(c.stats["bad_snapshots"]) == 0
		(
			out
			. append(
				{
					"seat": s["seat"],
					"name": c.name,
					"ship": s["ship"],
					"entry": s["entry"],
					"session": c.session_id,
					"picked": s["picked"],
					"rejects": s["rejects"],
					"stats": c.stats,
					"snaps": Array(c.snapshot_log),
				}
			)
		)
	_write({"why": why, "ok": ok, "clients": out})
	_done = true
	quit(0 if ok else 1)


func _write(doc: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(log_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc))
		f.close()


func _parse(args: PackedStringArray) -> bool:
	var i: int = 0
	while i < args.size():
		var flag: String = args[i]
		if flag == "--no-commands":
			commands = false
		elif flag == "--full-probe":
			full_probe = true
		elif i + 1 < args.size():
			var v: String = args[i + 1]
			i += 1
			match flag:
				"--url":
					url = v
				"--first":
					first = v.to_int()
				"--count":
					count = v.to_int()
				"--ships":
					ships = v.to_int()
				"--log":
					log_path = v
				"--max-s":
					max_s = v.to_float()
				_:
					return false
		else:
			return false
		i += 1
	return url != "" and log_path != ""
