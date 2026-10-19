class_name NetServer
extends Node
## The authoritative headless server loop (T041, FT-NET-002): owns the SimWorld built by
## an M1Encounter, steps it at 60 Hz from its own accumulator, feeds it the commands
## ServerSession validated, routes its events, and every SNAPSHOT_TICKS ticks hands a
## SimCopy to the net thread (NetTransport), which encodes and sends the 30 Hz
## snapshots off the sim thread (FT-NET-040, D111). app/main.gd composes it from the
## command line (ServerMain); tests add it to their scene tree.

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

var _next_snapshot_tick: int = 0
var _started_us: int = 0


## Builds the world and starts listening; returns the error, OK on success. port 0
## picks a free port (see port()).
func start(
	m1: M1Encounter,
	port: int,
	bind_address: String,
	dev_all: bool = false,
	host_secret: String = ""
) -> Error:
	encounter = m1
	world = encounter.build()
	if world == null:
		push_error("encounter does not validate: %s" % [encounter.validate()])
		return ERR_INVALID_DATA
	session = ServerSession.new(transport, world)
	session.dev_all = dev_all
	session.host_secret = host_secret
	var err: Error = transport.start(port, bind_address)
	if err != OK:
		return err
	_started_us = Time.get_ticks_usec()
	_next_snapshot_tick = world.tick
	return OK


func port() -> int:
	return transport.port()


func _process(delta: float) -> void:
	if session == null:
		return
	var now_us: int = Time.get_ticks_usec()
	session.process(now_us)
	var t0: int = Time.get_ticks_usec()
	var ticks: int = world.advance(delta)
	if ticks > 0:
		tick_us_max = maxi(tick_us_max, (Time.get_ticks_usec() - t0) / ticks)
		session.after_ticks(world.drain_events())
		if world.tick >= _next_snapshot_tick:
			transport.post_state(SimCopy.of(world))
			_next_snapshot_tick = world.tick + SNAPSHOT_TICKS
	if run_for > 0.0 and now_us - _started_us > run_for * 1_000_000.0:
		get_tree().quit(0)


func _exit_tree() -> void:
	transport.stop()
