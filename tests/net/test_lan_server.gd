extends GdUnitTestSuite
## L3 (T047): a running NetServer's beacon is listed by a LanBrowser over loopback, and
## a client joins it by the discovered host and by a typed address. The browser binds
## an ephemeral port on 127.0.0.1 and the beacon sends there, since one machine allows
## one listener on the discovery port and the limited broadcast doesn't loop back.

const TIMEOUT_MS: int = 8000

var _server: NetServer
var _browser: LanBrowser
var _clients: Array[NetClient] = []


func after_test() -> void:
	for c: NetClient in _clients:
		c.drop()
	_clients.clear()
	if _browser != null:
		_browser.stop()
		_browser = null
	if _server != null:
		_server.queue_free()
		_server = null
	await get_tree().process_frame


func _until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		_browser.poll(Time.get_ticks_usec())
		for c: NetClient in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _join(url: String) -> NetClient:
	var c: NetClient = NetClient.new()
	assert_int(c.connect_to(url)).is_equal(OK)
	_clients.append(c)
	return c


# FT: FT-NET-012, FT-NET-013
# The server's beacon lists it with its name, ports, protocol, player count and state;
# a client joins by the listed host's URL and another by a manual address. The list
# follows the player count.
func test_running_server_is_listed_and_joinable_by_host_and_address() -> void:
	_browser = LanBrowser.new(NetProtocol.PROTOCOL_VERSION)
	assert_int(_browser.start(0, "127.0.0.1")).is_equal(OK)
	_server = NetServer.new()
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	assert_int(_server.start(m1, 0, "127.0.0.1")).is_equal(OK)
	assert_int(_server.start_beacon("Bridge Party", _browser.local_port(), ["127.0.0.1"])).is_equal(
		OK
	)
	add_child(_server)
	var listed: Callable = func() -> bool: return _browser.hosts().size() == 1
	assert_bool(await _until(listed)).is_true()
	var host: LanBrowser.Host = _browser.hosts()[0]
	assert_str(host.name).is_equal("Bridge Party")
	assert_str(host.address).is_equal("127.0.0.1")
	assert_int(host.ws_port).is_equal(_server.port())
	assert_int(host.http_port).is_equal(_server.port() - 1)
	assert_int(host.cap).is_equal(64)
	assert_int(host.players).is_equal(0)
	assert_bool(host.compatible).is_true()
	assert_bool(host.running).is_false()
	# Join by the discovered host.
	var by_host: NetClient = _join(host.url())
	assert_bool(await _until(by_host.is_welcomed)).is_true()
	# Join by a typed address.
	var typed: JoinAddress = JoinAddress.parse("127.0.0.1:%d" % _server.port())
	assert_bool(typed.ok).is_true()
	var by_ip: NetClient = _join(typed.url)
	assert_bool(await _until(by_ip.is_welcomed)).is_true()
	assert_int(by_ip.session_id).is_not_equal(by_host.session_id)
	# The next beacons carry the player count and the active session.
	var counted: Callable = func() -> bool:
		var h: Array[LanBrowser.Host] = _browser.hosts()
		return h.size() == 1 and h[0].players == 2 and h[0].running
	assert_bool(await _until(counted, 4000)).is_true()
