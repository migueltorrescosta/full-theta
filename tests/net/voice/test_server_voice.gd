extends GdUnitTestSuite
## The session's voice seam (ServerVoice): the first Start calls start_session() once
## with the closed set, and sim events of the crewed ship say the ship computer's alert
## lines to the stations concerned. A spy VoiceService records the calls.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY


## Records start_session() and say() instead of synthesising.
class SpyService:
	extends VoiceService
	var starts: Array = []
	## [line id, args, audience as an Array].
	var said: Array = []

	func start_session(language: String, closed_set: Dictionary) -> void:
		starts.append([language, closed_set])

	func say(line_id: String, args: Dictionary, audience: PackedInt32Array) -> int:
		said.append([line_id, args, Array(audience)])
		return said.size()


var h: NetHarness
var _spy: SpyService


func before_test() -> void:
	h = NetHarness.new(self)
	_spy = SpyService.new()


func after_test() -> void:
	_spy.free()
	await h.free_all()


## A server with the _spy wired as ServerMain.make_voice does, and Tactical, Systems, Ops
## and a Viewer on the player ship.
func _crewed() -> Array:
	var server: NetServer = h.server()
	server.session.voice.voice = _spy
	_spy.computer_audience = server.session.computer_audience
	var crew: Array[NetClient] = await h.crew3(server)
	crew.append(await h.joined(server, "viewer", "viewer"))
	return [server, crew]


func _event(server: NetServer, kind: StringName, ship: int, value: float = 0.0) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	e.ship_id = ship
	e.faction = server.world.faction_of(ship)
	e.value = value
	return e


# FT: FT-AUD-018
func test_start_session_once_at_the_first_start_with_the_closed_set() -> void:
	var setup: Array = await _crewed()
	var server: NetServer = setup[0]
	var crew: Array[NetClient] = setup[1]
	server.session.language = "it"
	assert_array(_spy.starts).is_empty()
	assert_bool(await h.start(server, crew[0])).is_true()
	crew[1].set_ready(true)
	await h.wait(200)
	assert_int(_spy.starts.size()).is_equal(1)
	assert_str(_spy.starts[0][0]).is_equal("it")
	var closed: Dictionary = _spy.starts[0][1]
	var names: Array = []
	for id: int in server.world.ship_count():
		names.append(server.world.defs[id].display_name)
	assert_array(closed["ship_names"]).is_equal(names)
	# One ship of another faction in M1: its callsign is one of these.
	assert_array(closed["callsigns"]).is_equal(["U1", "H1", "F1", "N1"])
	assert_array(closed["npc_names"]).is_empty()


# FT: FT-AUD-006
func test_alert_lines_go_to_the_stations_concerned() -> void:
	var setup: Array = await _crewed()
	var server: NetServer = setup[0]
	var crew: Array[NetClient] = setup[1]
	var tac: int = crew[0].session_id
	var sys: int = crew[1].session_id
	var ops: int = crew[2].session_id
	var events: Array[SimEvent] = [
		_event(server, &"shield_low", PLAYER, 0.24),
		_event(server, &"fault", PLAYER),
		_event(server, &"proximity", PLAYER, 3.0),
		_event(server, &"hit", PLAYER, 10.0),
		_event(server, &"shield_low", ENEMY, 0.1),
	]
	server.session.after_ticks(events)
	(
		assert_array(_spy.said)
		. is_equal(
			[
				["computer.shields_low", {"pct": 24}, [tac, sys]],
				["computer.subsystem_fault", {}, [sys]],
				["computer.collision_warning", {}, [tac]],
			]
		)
	)
	# Hull at or under 25 %: "Hull critical" once to every crew station (not the Viewer).
	var damage: DamageTable = server.world.damage
	var hull: int = damage.hull_row(PLAYER)
	damage.health[hull] = server.world.defs[PLAYER].hull_max * 0.2
	_spy.said.clear()
	server.session.after_ticks([_event(server, &"hit", PLAYER), _event(server, &"hit", PLAYER)])
	assert_array(_spy.said).is_equal([["computer.hull_critical", {}, [tac, sys, ops]]])
	# Re-armed once repaired above it.
	damage.health[hull] = server.world.defs[PLAYER].hull_max
	server.session.after_ticks([_event(server, &"hit", PLAYER)])
	damage.health[hull] = server.world.defs[PLAYER].hull_max * 0.1
	server.session.after_ticks([_event(server, &"hit", PLAYER)])
	assert_int(_spy.said.size()).is_equal(2)
