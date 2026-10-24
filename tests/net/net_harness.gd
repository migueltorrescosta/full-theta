class_name NetHarness
extends RefCounted
## Shared helpers for the L3 network tests (and the L4 bots, T048): a NetServer on a
## free port in the test's scene tree, NetClients, and polling that never assumes a
## speed: every wait is "until a condition holds or a generous timeout passes", so the
## suites hold on 2 loaded cores (tools/gate.sh l3 runs them under taskset -c 0,1).
## Each client's delivered events are collected in events[client] while polling.

const PLAYER: int = M1Encounter.PLAYER_SHIP
const ENEMY: int = M1Encounter.ENEMY_SHIP
const TIMEOUT_MS: int = 8000

var node: Node
var servers: Array[NetServer] = []
var clients: Array[NetClient] = []
## NetClient -> Array[Dictionary] of every event delivered so far.
var events: Dictionary = {}


func _init(owner: Node) -> void:
	node = owner


## A listening server on 127.0.0.1 port 0 with the M1 encounter; grace_s is the
## reconnect grace (--grace-s). Not started: the lobby is open.
func server(dev_all: bool = false, grace_s: float = 10.0, host_secret: String = "") -> NetServer:
	var s: NetServer = NetServer.new()
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	m1.science = load("res://content/science/science.tres") as ScienceDef
	if s.start(m1, 0, "127.0.0.1", dev_all, host_secret) != OK:
		return null
	s.session.sessions.grace_us = int(grace_s * 1_000_000.0)
	node.add_child(s)
	servers.append(s)
	return s


## A connecting client (token "" for a new session).
func client(s: NetServer, name: String, token: String = "", secret: String = "") -> NetClient:
	var c: NetClient = NetClient.new()
	c.name = name
	c.token = token
	c.host_secret = secret
	c.connect_to("ws://127.0.0.1:%d" % s.port())
	clients.append(c)
	events[c] = []
	return c


## Polls every client each frame until cond holds or the timeout passes.
func until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while true:
		_poll()
		if cond.call():
			return true
		if Time.get_ticks_msec() >= end:
			return false
		await node.get_tree().process_frame
	return false


## Polls for ms milliseconds.
func wait(ms: int) -> void:
	await until(func() -> bool: return false, ms)


## A welcomed client.
func welcomed(s: NetServer, name: String, token: String = "", secret: String = "") -> NetClient:
	var c: NetClient = client(s, name, token, secret)
	await until(c.is_welcomed)
	return c


## Picks (ship, entry) and waits for the answer; true if accepted, and then for the
## full snapshot of the new view.
func pick(c: NetClient, entry: String, ship: int = PLAYER) -> bool:
	var fulls: int = c.view.full_count
	var n: int = (events[c] as Array).size()
	c.pick(ship, entry)
	var answer: Dictionary = await next_event(c, NetProtocol.EVENT_PICKED, n)
	if answer.is_empty() or answer["payload"]["reason"] != "":
		return false
	return await until(func() -> bool: return c.view.full_count > fulls)


## A welcomed client holding a pick, with its full snapshot applied.
func joined(s: NetServer, name: String, entry: String, ship: int = PLAYER) -> NetClient:
	var c: NetClient = await welcomed(s, name)
	await pick(c, entry, ship)
	return c


## Three crew clients covering the six stations (Tactical, Systems, Ops).
func crew3(s: NetServer) -> Array[NetClient]:
	var out: Array[NetClient] = []
	for entry: String in ["tactical", "systems", "ops"]:
		out.append(await joined(s, entry, entry))
	return out


## Presses Start and waits until the run started and the sim stepped.
func start(s: NetServer, c: NetClient) -> bool:
	var tick: int = s.world.tick
	c.set_ready(true)
	return await until(func() -> bool: return s.world.tick > tick + 2)


## The first event of a type at or after index from in the client's log matching
## pred (Callable(event) -> bool, or none), waiting for it; {} on timeout.
func next_event(
	c: NetClient, type: String, from: int = 0, pred: Callable = Callable()
) -> Dictionary:
	var found: Array[Dictionary] = []
	var look: Callable = func() -> bool:
		var seen: Array = events[c]
		for i: int in range(from, seen.size()):
			var e: Dictionary = seen[i]
			if e["type"] == type and (not pred.is_valid() or pred.call(e)):
				found.append(e)
				return true
		return false
	await until(look)
	return found[0] if not found.is_empty() else {}


## Events of a type delivered to the client so far.
func events_of(c: NetClient, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events[c]:
		if e["type"] == type:
			out.append(e)
	return out


## The last event of a type so far, or {}.
func last_event(c: NetClient, type: String) -> Dictionary:
	var all: Array[Dictionary] = events_of(c, type)
	return all[-1] if not all.is_empty() else {}


func mark(c: NetClient) -> int:
	_poll()
	return (events[c] as Array).size()


## The server-side session of a client.
func session_of(s: NetServer, c: NetClient) -> NetSession:
	return s.session.sessions.get_session(c.token)


## Drops a client (no Bye) and waits until the server noticed.
func drop(s: NetServer, c: NetClient) -> bool:
	var session: NetSession = session_of(s, c)
	c.drop()
	clients.erase(c)
	return await until(func() -> bool: return not session.connected())


## Waits until a session's grace ran out and the server lapsed it.
func lapsed(session: NetSession) -> bool:
	return await until(func() -> bool: return session.lapsed and session.entry == "")


## Drops every client and frees the servers (after_test).
func free_all() -> void:
	for c: NetClient in clients:
		c.drop()
	clients.clear()
	events.clear()
	for s: NetServer in servers:
		s.queue_free()
	servers.clear()
	await node.get_tree().process_frame


func _poll() -> void:
	for c: NetClient in clients:
		c.poll()
		(events[c] as Array).append_array(c.take_events())
