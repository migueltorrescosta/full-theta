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

## Ticks between snapshots: 60 Hz sim, 30 Hz snapshots (D70).
const SNAPSHOT_TICKS: int = 2

var encounter: M1Encounter
var world: SimWorld
var transport: NetTransport = NetTransport.new()
var session: ServerSession
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

var _next_snapshot_tick: int = 0
## While the sim doesn't step (lobby, pause), when the next state copy goes out (us).
var _next_idle_post_us: int = 0
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
	session = ServerSession.new(transport, world)
	session.dev_all = dev_all
	session.host_secret = host_secret
	transport.probe = probe != null
	var err: Error = transport.start(port, address)
	if err != OK:
		return err
	_started_us = Time.get_ticks_usec()
	_next_snapshot_tick = world.tick
	return OK


func port() -> int:
	return transport.port()


## Serves the web export in `root` over plain HTTP on the bind address at port() - 1
## (FT-NET-030, D108). Call after start().
func start_http(root: String) -> Error:
	http = StaticServer.new(root)
	var err: Error = http.listen(port() - 1, bind_address)
	if err != OK:
		http = null
	return err


## Broadcasts this server on the LAN once a second (FT-NET-012). `destinations` are the
## addresses the datagram goes to (tests use loopback). Call after start().
func start_beacon(
	server_name: String,
	discovery_port: int = LanBeacon.DISCOVERY_PORT,
	destinations: PackedStringArray = [LanBeacon.BROADCAST_ADDRESS]
) -> Error:
	var http_port: int = http.local_port() if http != null else port() - 1
	beacon = LanBeacon.new(NetProtocol.PROTOCOL_VERSION, server_name, port(), http_port)
	beacon.player_cap = session.max_sessions
	var err: Error = beacon.start(discovery_port, destinations)
	if err != OK:
		beacon = null
	return err


## Open WebSocket connections, including ones that haven't said Hello yet (the idle
## exit counts these; FT-NET-003). Lags the net thread by up to 20 ms.
func connections() -> int:
	return (transport.stats().get("conns", {}) as Dictionary).size()


## Sessions with a connected client.
func players() -> int:
	var n: int = 0
	for s: NetSession in session.by_id.values():
		if s.connected():
			n += 1
	return n


## True while any session exists, connected or within its reconnect grace: a lobby
## with players or a run, which a relaunched host may rejoin (TECH-8). PROVISIONAL:
## T043 may narrow it to a started run.
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
	t[1] = Time.get_ticks_usec()
	var ticks: int = 0
	# The sim steps only after a Start and outside a pause (FT-NET-034); snapshots keep
	# flowing at 30 Hz of wall clock meanwhile, so joining and rejoining clients get theirs.
	if not session.sim_running():
		if now_us >= _next_idle_post_us:
			_post_state()
			_next_idle_post_us = now_us + SNAPSHOT_TICKS * 1_000_000 / 60
	else:
		ticks = world.advance(delta)
		t[2] = Time.get_ticks_usec()
		t[3] = t[2]
		t[4] = t[2]
		if ticks > 0:
			tick_us_max = maxi(tick_us_max, (t[2] - t[1]) / ticks)
			session.after_ticks(world.drain_events())
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
