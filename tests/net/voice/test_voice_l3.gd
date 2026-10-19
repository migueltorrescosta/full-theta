extends GdUnitTestSuite
## L3: an in-process NetServer with a VoiceService next to it (spy synth, a temp
## prerender directory) and two NetClients over loopback: the target gets each line's
## voice_line event and then its VOICE parts in order, chunked on the voice stream; the
## bystander gets neither.

const DIR: String = "user://test_voice_l3"
const TIMEOUT_MS: int = 4000
## Small chunks, so every clip goes in several (FT-NET-038).
const CHUNK: int = 256

var _server: NetServer
var _svc: VoiceService
var _fx: VoiceFixture
var _clients: Array[NetClient] = []


func after_test() -> void:
	for c: NetClient in _clients:
		c.drop()
	_clients.clear()
	if _svc != null:
		_svc.queue_free()
	if _server != null:
		_server.queue_free()
	await get_tree().process_frame
	if _fx != null:
		_fx.clean()


func _until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for c: NetClient in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _client(name: String) -> NetClient:
	var c: NetClient = NetClient.new()
	c.name = name
	assert_int(c.connect_to("ws://127.0.0.1:%d" % _server.port())).is_equal(OK)
	_clients.append(c)
	return c


func _voice_lines(c: NetClient) -> Array[Dictionary]:
	return c.take_events().filter(
		func(e: Dictionary) -> bool: return e["type"] == VoiceService.EVENT_VOICE_LINE
	)


# FT: FT-AUD-019, FT-NET-038, FT-ARC-019, FT-AUD-018
func test_voice_goes_to_the_target_client_only() -> void:
	_fx = VoiceFixture.new(DIR)
	_fx.write("en")
	_server = NetServer.new()
	_server.transport.chunk_size = CHUNK
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	assert_int(_server.start(m1, 0, "127.0.0.1")).is_equal(OK)
	add_child(_server)
	_svc = VoiceService.new(_server.transport, _fx.factory())
	_svc.prerender_dir = DIR
	_svc.tick_source = func() -> int: return _server.world.tick
	add_child(_svc)
	var target: NetClient = _client("comms")
	var bystander: NetClient = _client("helm")
	(
		assert_bool(
			await _until(func() -> bool: return target.is_welcomed() and bystander.is_welcomed())
		)
		. is_true()
	)
	_svc.npc_audience = func(_npc: String) -> PackedInt32Array:
		return PackedInt32Array([target.session_id])
	_svc.computer_audience = func(_ship: int, stations: PackedStringArray) -> PackedInt32Array:
		return (
			PackedInt32Array([target.session_id]) if stations.has("comms") else PackedInt32Array()
		)
	_svc.start_session("en", {"callsigns": ["Viper Three"], "npc_names": ["Mara Quill"]})
	assert_bool(await _until(_svc.closed_set_done)).is_true()
	_fx.log.clear()
	target.take_events()
	bystander.take_events()
	var before: int = target.arrivals.size()
	var stitched: int = _svc.say_computer(
		0,
		PackedStringArray(["comms"]),
		"computer.contact",
		{"callsign": "Viper Three", "bearing": 342, "range": 18}
	)
	var free: int = _svc.say_npc_free("trader_1", "Hold position. We are coming about!")
	_svc.say_npc("trader_1", "npc.distress", {"npc": "Mara Quill"})
	_svc.say_computer(0, PackedStringArray(["comms"]), "computer.hull_critical")
	assert_bool(await _until(func() -> bool: return target.stats["voice"] >= 4)).is_true()
	# Let anything stray arrive.
	await _until(func() -> bool: return false, 300)
	# One synthesis request: the free text (FT-ARC-019).
	assert_int(_fx.log.size()).is_equal(1)
	var lines: Array[Dictionary] = _voice_lines(target)
	assert_int(lines.size()).is_equal(4)
	var clips: Array = lines.map(func(e: Dictionary) -> int: return e["payload"]["clip"])
	assert_int(clips[0]).is_equal(stitched)
	assert_int(clips[1]).is_equal(free)
	assert_bool(lines[3]["payload"]["local"]).is_true()
	# Event before its audio, parts in order, on the voice stream.
	var order: PackedByteArray = target.arrivals.slice(before)
	assert_int(order[0]).is_equal(NetChunker.STREAM_CONTROL)
	var voice: Array = target.voice_clips.map(
		func(v: Dictionary) -> Array: return [v["clip"], v["part"], v["last"]]
	)
	var free_parts: Array = voice.filter(func(v: Array) -> bool: return v[0] == free)
	assert_array(free_parts).is_equal([[free, 0, false], [free, 1, true]])
	assert_int(voice.filter(func(v: Array) -> bool: return v[0] == stitched).size()).is_equal(1)
	assert_int(voice.size()).is_equal(4)
	assert_int(order.count(NetChunker.STREAM_VOICE)).is_equal(4)
	var first_voice: int = order.find(NetChunker.STREAM_VOICE)
	# The four events (high lane) went before any voice chunk (low lane).
	assert_int(order.slice(0, first_voice).count(NetChunker.STREAM_CONTROL)).is_equal(4)
	for v: Dictionary in target.voice_clips:
		var e: int = clips.find(v["clip"])
		assert_int(e).is_greater_equal(0)
	# The stitched clip is larger than a chunk, so it went in chunks, and arrived whole.
	var pcm: PackedByteArray = target.voice_clips[0]["pcm"]
	assert_int(pcm.size()).is_greater(CHUNK * 2)
	assert_str(_fx.decode("en", "computer", pcm)[1]).is_equal("name:11")
	# The bystander: no voice_line and not one voice byte.
	assert_int(_voice_lines(bystander).size()).is_equal(0)
	assert_int(bystander.stats["voice"]).is_equal(0)
	assert_int(bystander.arrivals.count(NetChunker.STREAM_VOICE)).is_equal(0)
