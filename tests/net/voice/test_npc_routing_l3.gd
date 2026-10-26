extends GdUnitTestSuite
## E10 / #10: spoken lines from the sim (&"say" events) are routed: an NPC line to the
## holder of that NPC's conversation claim only, a subtitle for every Comms holder while
## nobody holds it (PROVISIONAL, Q8), a ship-computer line to the stations concerned.
## A spy VoiceService records the calls; two Comms players share the player ship. The
## claim is a stub on NetClaims (strand C builds the real "npc" claim kind and cards).

const PLAYER: int = NetHarness.PLAYER
const NPC: String = "trader_1"


## Records say() and say_subtitle() instead of synthesising.
class SpyService:
	extends VoiceService
	## [kind ("clip" or "subtitle"), line id, args, audience as an Array].
	var said: Array = []

	func say(line_id: String, args: Dictionary, audience: PackedInt32Array) -> int:
		said.append(["clip", line_id, args, Array(audience)])
		return said.size()

	func say_subtitle(line_id: String, args: Dictionary, audience: PackedInt32Array) -> int:
		said.append(["subtitle", line_id, args, Array(audience)])
		return said.size()


var h: NetHarness
var _spy: SpyService


func before_test() -> void:
	h = NetHarness.new(self)
	_spy = SpyService.new()
	_spy.dialogue = DialogueLines.load_dir()


func after_test() -> void:
	_spy.free()
	await h.free_all()


## Two Comms players (Ops and Parley) and an Engineering player (Systems) on the player ship.
func _crew() -> Array:
	var server: NetServer = h.server()
	server.session.voice.voice = _spy
	_spy.computer_audience = server.session.computer_audience
	_spy.npc_audience = server.session.npc_audience
	var crew: Array[NetClient] = []
	for entry: String in ["ops", "parley", "systems"]:
		crew.append(await h.joined(server, entry, entry))
	server.session.npc_cards = {NPC: "card_7"}
	return [server, crew]


func _say(server: NetServer, line_id: String, args: Dictionary) -> void:
	var cmd: SayCommand = SayCommand.new()
	cmd.ship_id = PLAYER
	cmd.line_id = line_id
	cmd.npc_id = NPC if line_id.begins_with("npc.") else ""
	cmd.stations = args.get("stations", [])
	cmd.args = args.get("args", {})
	server.world.submit(cmd)
	server.world.step()
	var fresh: Array[SimEvent] = []
	fresh.assign(server.world.events.filter(func(e: SimEvent) -> bool: return e.kind == &"say"))
	server.world.events.clear()
	server.session.after_ticks(fresh)


# FT: FT-AUD-005, FT-COM-006, FT-AUD-010
func test_npc_line_goes_to_the_claimer_only_and_unclaimed_is_subtitle_only() -> void:
	var setup: Array = await _crew()
	var server: NetServer = setup[0]
	var crew: Array[NetClient] = setup[1]
	var first: int = crew[0].session_id
	var second: int = crew[1].session_id
	var args: Dictionary = {"args": {"npc": "Rosa"}}
	# Nobody holds the claim: a subtitle for every Comms holder, no clip.
	_say(server, "npc.hail_trader", args)
	assert_array(_spy.said).has_size(1)
	assert_str(_spy.said[0][0]).is_equal("subtitle")
	assert_array(_spy.said[0][3]).contains_exactly_in_any_order([first, second])
	assert_dict(_spy.said[0][2]).is_equal({"npc": "Rosa"})
	# The second player claims the NPC's card: only they get the clip.
	_spy.said.clear()
	assert_bool(server.session.claims.claim(PLAYER, "npc:card_7", second)).is_true()
	_say(server, "npc.hail_trader", args)
	assert_array(_spy.said).is_equal([["clip", "npc.hail_trader", {"npc": "Rosa"}, [second]]])
	# Released again: back to subtitles for both.
	_spy.said.clear()
	server.session.claims.release(PLAYER, "npc:card_7", second)
	_say(server, "npc.hail_trader", args)
	assert_str(_spy.said[0][0]).is_equal("subtitle")


# FT: FT-AUD-006, FT-AUD-010
func test_computer_line_goes_to_the_stations_concerned_only() -> void:
	var setup: Array = await _crew()
	var server: NetServer = setup[0]
	var crew: Array[NetClient] = setup[1]
	var engineer: int = crew[2].session_id
	var ops: int = crew[0].session_id
	_say(server, "computer.subsystem_fault", {"stations": ["engineering"]})
	assert_array(_spy.said).is_equal([["clip", "computer.subsystem_fault", {}, [engineer]]])
	_spy.said.clear()
	_say(server, "computer.jump_ready", {"stations": ["relay", "comms"]})
	assert_int(_spy.said.size()).is_equal(1)
	assert_str(_spy.said[0][0]).is_equal("clip")
	assert_array(_spy.said[0][3]).contains_exactly_in_any_order([ops, crew[1].session_id])
	_spy.said.clear()
	_say(server, "computer.jump_ready", {"stations": ["helm"]})
	assert_array(_spy.said[0][3]).is_empty()


# FT: FT-AUD-018
func test_npc_names_join_the_closed_set() -> void:
	var server: NetServer = h.server()
	server.session.voice.npc_names = ["Rosa", "Captain Voss"]
	var closed: Dictionary = server.session.voice.closed_set([server.world.faction_of(PLAYER)])
	assert_array(closed["npc_names"]).is_equal(["Rosa", "Captain Voss"])
