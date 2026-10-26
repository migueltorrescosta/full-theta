class_name NetServer
extends Node
## The authoritative headless server loop (T041, FT-NET-002): owns the SimWorld built by
## an M1Encounter, steps it at 60 Hz from its own accumulator, feeds it the commands
## ServerSession validated, routes its events, and every SNAPSHOT_TICKS ticks hands a
## SimCopy to the net thread (NetTransport), which encodes and sends the 30 Hz
## snapshots off the sim thread (FT-NET-040, D111). app/main.gd composes it from the
## command line (ServerMain); tests add it to their scene tree.
##
## Two optional LAN services share the loop (T046, T047): the static HTTP server for
## browser stations (StaticServer, on the bind address at the WebSocket port - 1, D108)
## and the discovery beacon (LanBeacon). Both are polled at the end of the frame, after
## the sim stepped and the state copy was handed over, so the tick never waits on them;
## HTTP gets a 400 us budget per frame (FT-NET-039).
##
## After an outcome the crew may vote to run again (NetRunReset, D178): restart_run()
## then swaps in a world built from scratch everywhere it is held (here, the session,
## the voice seam, the net thread's encoder), with a fresh command log.

## Ticks between snapshots: 60 Hz sim, 30 Hz snapshots (D70).
const SNAPSHOT_TICKS: int = 2
## How often the snapshot-age summary line is written (us).
const STATS_PERIOD_US: int = 10_000_000

var encounter: M1Encounter
var world: SimWorld
# --- strand A ---
## Steps the world with the director's before_tick (E07); rebuilt with every new world.
var host: ScenarioHost
## The director (or Shakedown's training driver): anything with before_tick(api). Made on the
## first step of a run from driver_factory(difficulty preset), so it sees the lobby's toggles;
## null with no factory (the M1 encounter).
var driver: RefCounted
var driver_factory: Callable
# --- end strand A ---
var transport: NetTransport = NetTransport.new()
var session: ServerSession
var run_reset: NetRunReset
## Seconds after which the server quits by itself (0: never); for smoke runs.
var run_for: float = 0.0
## Sim timing over the last frames that stepped (us), for logs and tests.
var tick_us_max: int = 0
## Address the WebSocket listener (and the HTTP server) bind to.
var bind_address: String = ""
## Static HTTP server for the web export, or null when off (start_http).
var http: StaticServer
## Longest static HTTP poll so far (us), for logs and tests (FT-NET-039).
var http_us_max: int = 0
## LAN discovery beacon, or null when off (start_beacon).
var beacon: LanBeacon
## The load gate's probe (`--probe-out`, D161), or null; set before start().
var probe: LoadProbe

## The session log (D199), or null until start_session_log(); other systems add their
## events and counters to it (SessionLog).
var session_log: SessionLog
var age_stats: SnapshotAgeStats = SnapshotAgeStats.new()

var _next_snapshot_tick: int = 0
var _next_stats_us: int = 0
var _logged_counters: Dictionary = {}
## While the sim doesn't step (lobby, pause), when the next snapshot goes out (us), and
## whether the net thread already holds the idle world's state.
var _next_idle_post_us: int = 0
var _idle_state_posted: bool = false
var _started_us: int = 0


## Builds the world and starts listening; returns the error, OK on success. port 0
## picks a free port (see port()).
func start(
	m1: M1Encounter, port: int, address: String, dev_all: bool = false, host_secret: String = ""
) -> Error:
	encounter = m1
	bind_address = address
	world = encounter.build()
	if world == null:
		push_error("encounter does not validate: %s" % [encounter.validate()])
		return ERR_INVALID_DATA
	host = ScenarioHost.new(world)  # strand A
	session = ServerSession.new(transport, world)
	session.dev_all = dev_all
	session.host_secret = host_secret
	transport.probe = probe != null
	run_reset = NetRunReset.new(session, restart_run)
	run_reset.decisions = _director_decisions  # strand E
	var err: Error = transport.start(port, address)
	if err != OK:
		return err
	_started_us = Time.get_ticks_usec()
	_next_snapshot_tick = world.tick
	return OK


func port() -> int:
	return transport.port()


## Opens the session log at `path` (SessionLog.default_path() in a normal session): the
## snapshot-age summary every STATS_PERIOD_US and a final summary on exit (D199). Call
## after start().
func start_session_log(path: String) -> Error:
	session_log = SessionLog.open(path)
	if session_log == null:
		return ERR_CANT_CREATE
	session.session_log = session_log
	session.add_handler(NetProtocol.Type.CLIENT_STATS, _on_client_stats)
	session_log.event(
		"start", {"port": port(), "bind": bind_address, "protocol": NetProtocol.PROTOCOL_VERSION}
	)
	_next_stats_us = Time.get_ticks_usec() + STATS_PERIOD_US
	return OK


## Adds each client's full snapshots and stalls on its current connection (cumulative),
## so a phone that keeps resyncing shows next to its ages (D199).
func _add_resyncs(window: Dictionary) -> void:
	var by_session: Dictionary = {}
	for c: Dictionary in (transport.stats().get("conns", {}) as Dictionary).values():
		by_session[c["session"]] = c
	for line: Dictionary in window["clients"]:
		var c: Dictionary = by_session.get(line["session"], {})
		line["fulls"] = c.get("fulls", 0)
		line["stalls"] = c.get("stalls", 0)


## A client's report of snapshot arrival times (D199).
func _on_client_stats(conn: int, msg: Dictionary, _now_us: int) -> void:
	var from: NetSession = session.by_conn.get(conn)
	var pairs: PackedInt64Array = msg["pairs"]
	if from == null or pairs.size() > 2 * NetProtocol.MAX_STATS_PAIRS:
		return
	var c: SnapshotAgeStats.Client = age_stats.client_for(from.id, from.name, from.client_kind)
	c.user_agent = NetProtocol.clip_utf8(msg["ua"], NetProtocol.MAX_UA_BYTES)
	age_stats.report(c, msg["sent_us"], LoadProbe.unix_us(), pairs, transport.stamp_of)


## The run reset (FT-M1-012, D178): a new world from the encounter (its command log
## starts empty), every ship back in the lobby with its picks kept, and the next
## snapshot full for every client. NetRunReset calls it when the vote passes.
func restart_run() -> void:
	world = encounter.build()
	host = ScenarioHost.new(world)  # strand A
	driver = null
	transport.reset_snapshots()
	session.restart(world)
	_next_snapshot_tick = world.tick
	_idle_state_posted = false


# --- strand E ---
## The director's decisions so far for the debrief; none with another driver.
func _director_decisions() -> Array:
	if driver is Director:
		return (driver as Director).decisions()
	return []


# --- end strand E ---
## Serves the web export in `root` over plain HTTP on the bind address at port() - 1
## (FT-NET-030, D108). Call after start().
func start_http(root: String) -> Error:
	http = StaticServer.new(root)
	var err: Error = http.listen(port() - 1, bind_address)
	if err != OK:
		http = null
	return err


## Broadcasts this server on the LAN once a second (FT-NET-012), with HTTP port 0
## when start_http() wasn't called (or failed). `destinations` are the addresses the
## datagram goes to (tests use loopback). Call after start(), and after start_http().
## ServerMain calls it only when bound to a non-loopback address.
func start_beacon(
	server_name: String,
	discovery_port: int = LanBeacon.DISCOVERY_PORT,
	destinations: PackedStringArray = [LanBeacon.BROADCAST_ADDRESS]
) -> Error:
	var http_port: int = http.local_port() if http != null else 0
	beacon = LanBeacon.new(NetProtocol.PROTOCOL_VERSION, server_name, port(), http_port)
	beacon.player_cap = session.max_sessions
	var err: Error = beacon.start(discovery_port, destinations)
	if err != OK:
		beacon = null
	return err


## Open WebSocket connections, including ones that haven't said Hello yet. Lags the
## net thread by up to 20 ms.
func connections() -> int:
	return transport.open_connections()


## Connections bound to a session: what keeps the idle exit away (FT-NET-003), so a
## socket that never says Hello doesn't keep the server up. Lags by up to 20 ms.
func bound_connections() -> int:
	return transport.bound_connections()


## Sessions with a connected client.
func players() -> int:
	var n: int = 0
	for s: NetSession in session.by_id.values():
		if s.connected():
			n += 1
	return n


## True while any session exists, connected or within its reconnect grace: a lobby
## with players or a run. One meaning for both uses: the pid file's session_active (a
## relaunched host offers to rejoin, or asks before terminating, rather than killing
## a server others are on; TECH-8) and the beacon's flag. A started run is not the
## test: a lobby with players must not be killed without asking either.
func session_active() -> bool:
	return not session.by_id.is_empty()


## The connected host's session id (D127), or -1.
func host_session() -> int:
	for s: NetSession in session.by_id.values():
		if s.is_host and s.connected():
			return s.id
	return -1


func _process(delta: float) -> void:
	if session == null:
		return
	var s0: PackedInt64Array = probe.sched() if probe != null else PackedInt64Array()
	var now_us: int = Time.get_ticks_usec()
	# Stamps for the probe: start, after process, after the sim, after after_ticks,
	# after the capture.
	var t: PackedInt64Array = PackedInt64Array([now_us, 0, 0, 0, 0])
	session.process(now_us)
	run_reset.process()
	t[1] = Time.get_ticks_usec()
	var ticks: int = 0
	# The sim steps only after a Start and outside a pause (FT-NET-034); snapshots keep
	# flowing at 30 Hz of wall clock meanwhile, so joining and rejoining clients get theirs.
	# The world doesn't change then: it is captured once and re-encoded from that copy,
	# and only while someone holds a pick (nobody else gets snapshots).
	if not session.sim_running():
		if now_us >= _next_idle_post_us and _picks() > 0:
			if _idle_state_posted:
				transport.repost_state()
			else:
				_post_state()
				_idle_state_posted = true
			_next_idle_post_us = now_us + SNAPSHOT_TICKS * 1_000_000 / 60
	else:
		_idle_state_posted = false
		if not host.holds(world):  # strand A: a test swapped the world
			host = ScenarioHost.new(world)
		if driver == null and driver_factory.is_valid():
			driver = driver_factory.call(StringName(session.toggles.preset))
		ticks = host.advance(
			delta, Callable(driver, &"before_tick") if driver != null else Callable()
		)
		t[2] = Time.get_ticks_usec()
		t[3] = t[2]
		t[4] = t[2]
		if ticks > 0:
			tick_us_max = maxi(tick_us_max, (t[2] - t[1]) / ticks)
			var events: Array[SimEvent] = world.drain_events()
			session.after_ticks(events)
			run_reset.after_ticks(events)
			t[3] = Time.get_ticks_usec()
			if world.tick >= _next_snapshot_tick:
				_post_state()
				_next_snapshot_tick = world.tick + SNAPSHOT_TICKS
			t[4] = Time.get_ticks_usec()
	if probe != null:
		if ticks > 0:
			probe.tick_frame(t, ticks, s0, probe.sched())
		# Counting picks and crewable ships is only needed until the window opens.
		var all_in: bool = (
			probe.phase == LoadProbe.Phase.WAITING
			and _picks() >= probe.expect_picks
			and session.launched.size() >= session.crew_ships().size()
		)
		if probe.update(all_in, session.launched.size()):
			get_tree().quit(0)
	_poll_lan_services()
	if session_log != null and now_us >= _next_stats_us:
		_next_stats_us = now_us + STATS_PERIOD_US
		var window: Dictionary = age_stats.window_summary()
		if (window["pooled"] as Dictionary)["n"] > 0:
			_add_resyncs(window)
			session_log.event("snapshot_age", window)
		# Counters as they stand, so a server that is killed (no final summary) still has them.
		if session_log.counters() != _logged_counters:
			_logged_counters = session_log.counters()
			session_log.event("counters", {"counters": _logged_counters})
	if run_for > 0.0 and now_us - _started_us > run_for * 1_000_000.0:
		get_tree().quit(0)


## Hands the net thread a copy of the state, stamped (unix us) before the capture so
## the snapshot age counts it (D161).
func _post_state() -> void:
	var stamp_us: int = LoadProbe.unix_us()
	transport.post_state(SimCopy.capture(world), stamp_us)


## After the tick: static HTTP within its budget, then the beacon (at most one datagram
## a second).
func _poll_lan_services() -> void:
	if http != null:
		var t0: int = Time.get_ticks_usec()
		http.poll(StaticServer.DEFAULT_BUDGET_US)
		http_us_max = maxi(http_us_max, Time.get_ticks_usec() - t0)
	if beacon != null:
		beacon.players = players()
		beacon.session_running = session_active()
		beacon.poll(Time.get_ticks_usec())


## Sessions holding a pick (the probe waits for all of them).
func _picks() -> int:
	var n: int = 0
	for s: NetSession in session.by_id.values():
		if s.has_pick():
			n += 1
	return n


func _exit_tree() -> void:
	transport.stop()
	if session_log != null:
		session_log.close({"snapshot_age": age_stats.total_summary(), "tick": world.tick})
	if probe != null:
		var sessions: Dictionary = {}
		for s: NetSession in session.by_id.values():
			sessions[s.id] = {"name": s.name, "ship": s.ship, "entry": s.entry}
		probe.write(
			transport.probe_dump(),
			sessions,
			{"ships": world.ship_count(), "tick": world.tick, "tick_us_max": tick_us_max}
		)
	if http != null:
		http.stop()
	if beacon != null:
		beacon.stop()
