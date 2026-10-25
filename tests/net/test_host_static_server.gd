extends GdUnitTestSuite
## The static HTTP server for the web export (net/static_server.gd), ported
## from the S3 spike's tests. Servers listen on a free port (port 0), so
## parallel loopback tests don't clash.

const MAX_PROBE: int = 8190

var _dir: String = ""
## Stopped in after_test, so a failed assertion doesn't leave the port bound.
var _server: StaticServer


func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://host_static_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	var body: PackedByteArray = PackedByteArray()
	body.resize(300_000)
	for i: int in range(body.size()):
		body[i] = i % 251
	_write(_dir + "/big.wasm", body)
	_write(_dir + "/big.wasm.gz", "pretend-gzip".to_utf8_buffer())
	_write(_dir + "/index.html", "<p>hi</p>".to_utf8_buffer())


func after_test() -> void:
	if _server != null:
		_server.stop()
		_server = null
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	DirAccess.remove_absolute(_dir)


func _write(path: String, data: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


## Sends one request and polls server and client until the response is in.
## Returns {"status": int, "headers": Dictionary, "body": PackedByteArray}.
func _fetch(server: StaticServer, request: String) -> Dictionary:
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", server.local_port())
	var raw: PackedByteArray = PackedByteArray()
	var sent: bool = false
	var deadline: int = Time.get_ticks_msec() + 3000
	var res: Dictionary = {}
	while Time.get_ticks_msec() < deadline and res.is_empty():
		server.poll(400)
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				tcp.put_data(request.to_utf8_buffer())
				sent = true
			var n: int = tcp.get_available_bytes()
			if n > 0:
				raw.append_array(tcp.get_data(n)[1])
			res = _parse(raw)
		OS.delay_usec(200)
	tcp.disconnect_from_host()
	return res


func _parse(raw: PackedByteArray) -> Dictionary:
	var text: String = raw.get_string_from_ascii()
	var end: int = text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines: PackedStringArray = text.left(end).split("\r\n")
	var headers: Dictionary = {}
	for line: String in lines.slice(1):
		headers[line.get_slice(":", 0).to_lower()] = line.substr(line.find(":") + 1).strip_edges()
	var length: int = int(headers.get("content-length", "0"))
	var status: int = int(lines[0].get_slice(" ", 1))
	if status == 304:
		length = 0
	if raw.size() < end + 4 + length:
		return {}
	return {"status": status, "headers": headers, "body": raw.slice(end + 4, end + 4 + length)}


func test_parse_request() -> void:
	var req: Dictionary = StaticServer.parse_request(
		"GET /index.wasm?v=2 HTTP/1.1\r\nHost: x\r\nAccept-Encoding: gzip, br"
	)
	assert_str(req["method"]).is_equal("GET")
	assert_str(req["path"]).is_equal("/index.wasm?v=2")
	assert_str(req["headers"]["accept-encoding"]).is_equal("gzip, br")
	assert_bool(StaticServer.parse_request("nonsense").is_empty()).is_true()


# FT: FT-NET-030
func test_resolve_stays_in_the_folder() -> void:
	assert_str(StaticServer.resolve("/")).is_equal("index.html")
	assert_str(StaticServer.resolve("/?name=a")).is_equal("index.html")
	assert_str(StaticServer.resolve("/index.pck?x")).is_equal("index.pck")
	assert_str(StaticServer.resolve("/../project.godot")).is_equal("")
	assert_str(StaticServer.resolve("/%2e%2e/x")).is_equal("")
	assert_str(StaticServer.resolve("/a/b.js")).is_equal("")
	assert_str(StaticServer.resolve("/.env")).is_equal("")


func test_mime_types() -> void:
	assert_str(StaticServer.mime_for("index.wasm")).is_equal("application/wasm")
	assert_str(StaticServer.mime_for("index.js")).starts_with("text/javascript")
	assert_str(StaticServer.mime_for("index.html")).starts_with("text/html")
	assert_str(StaticServer.mime_for("keepawake.webm")).is_equal("video/webm")
	assert_str(StaticServer.mime_for("keepawake.mp4")).is_equal("video/mp4")
	assert_str(StaticServer.mime_for("index.pck")).is_equal("application/octet-stream")


func test_accepts_gzip() -> void:
	assert_bool(StaticServer.accepts_gzip("gzip, deflate, br")).is_true()
	assert_bool(StaticServer.accepts_gzip("br;q=1.0, gzip;q=0.8")).is_true()
	assert_bool(StaticServer.accepts_gzip("gzip;q=0")).is_false()
	assert_bool(StaticServer.accepts_gzip("gzip; q=0.000")).is_false()
	assert_bool(StaticServer.accepts_gzip("gzip;q=0.001")).is_true()
	assert_bool(StaticServer.accepts_gzip("identity")).is_false()
	assert_bool(StaticServer.accepts_gzip("")).is_false()


# FT: FT-NET-030
func test_serves_gzip_etag_and_304_over_loopback() -> void:
	_server = StaticServer.new(_dir, 16384)
	var server: StaticServer = _server
	assert_int(server.listen(0, "127.0.0.1")).is_equal(OK)
	var plain: Dictionary = _fetch(server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\n\r\n")
	assert_int(plain["status"]).is_equal(200)
	assert_str(plain["headers"]["content-type"]).is_equal("application/wasm")
	assert_int((plain["body"] as PackedByteArray).size()).is_equal(300_000)
	assert_int((plain["body"] as PackedByteArray)[1000]).is_equal(1000 % 251)
	var gz: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nAccept-Encoding: gzip\r\n\r\n"
	)
	assert_str(gz["headers"]["content-encoding"]).is_equal("gzip")
	assert_str((gz["body"] as PackedByteArray).get_string_from_ascii()).is_equal("pretend-gzip")
	var etag: String = plain["headers"]["etag"]
	var again: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nIf-None-Match: %s\r\n\r\n" % etag
	)
	assert_int(again["status"]).is_equal(304)
	var missing: Dictionary = _fetch(server, "GET /nope.js HTTP/1.1\r\nHost: t\r\n\r\n")
	assert_int(missing["status"]).is_equal(404)
	var post: Dictionary = _fetch(server, "POST / HTTP/1.1\r\nHost: t\r\n\r\n")
	assert_int(post["status"]).is_equal(405)
	assert_str(post["headers"]["allow"]).is_equal("GET, HEAD")


# FT: FT-NET-030, FT-NET-046
func test_serves_one_byte_range_of_the_file_itself() -> void:
	_server = StaticServer.new(_dir, 16384)
	var server: StaticServer = _server
	assert_int(server.listen(0, "127.0.0.1")).is_equal(OK)
	var part: Dictionary = _fetch(
		server,
		"GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=10-19\r\nAccept-Encoding: gzip\r\n\r\n"
	)
	assert_int(part["status"]).is_equal(206)
	assert_str(part["headers"]["content-range"]).is_equal("bytes 10-19/300000")
	assert_str(part["headers"]["accept-ranges"]).is_equal("bytes")
	assert_bool(part["headers"].has("content-encoding")).is_false()
	var body: PackedByteArray = part["body"]
	assert_int(body.size()).is_equal(10)
	assert_int(body[0]).is_equal(10 % 251)
	var tail: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=-5\r\n\r\n"
	)
	assert_str(tail["headers"]["content-range"]).is_equal("bytes 299995-299999/300000")
	var open_end: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=299990-\r\n\r\n"
	)
	assert_int((open_end["body"] as PackedByteArray).size()).is_equal(10)
	var bad: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=400000-\r\n\r\n"
	)
	assert_int(bad["status"]).is_equal(416)
	assert_str(bad["headers"]["content-range"]).is_equal("bytes */300000")
	# A stale If-Range gets the whole file.
	var stale: Dictionary = _fetch(
		server, 'GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=0-9\r\nIf-Range: "x"\r\n\r\n'
	)
	assert_int(stale["status"]).is_equal(200)
	assert_int((stale["body"] as PackedByteArray).size()).is_equal(300_000)
	# Ranges don't stop a keep-alive connection from serving the next request.
	assert_int(server.ranges).is_equal(3)


# FT: FT-NET-030
func test_range_parsing_and_cache_control() -> void:
	assert_that(StaticServer.parse_range("bytes=0-0", 5)).is_equal(Vector2i(0, 0))
	assert_that(StaticServer.parse_range("bytes=2-", 5)).is_equal(Vector2i(2, 4))
	assert_that(StaticServer.parse_range("bytes=2-99", 5)).is_equal(Vector2i(2, 4))
	assert_that(StaticServer.parse_range("bytes=-2", 5)).is_equal(Vector2i(3, 4))
	assert_that(StaticServer.parse_range("bytes=-99", 5)).is_equal(Vector2i(0, 4))
	for bad: String in [
		"bytes=5-", "bytes=3-1", "bytes=0-1,3-4", "items=0-1", "bytes=-", "bytes=a-"
	]:
		assert_that(StaticServer.parse_range(bad, 5)).is_equal(Vector2i(-1, -1))
	assert_str(StaticServer.cache_control("index.html")).is_equal("no-cache")
	assert_str(StaticServer.cache_control("index.wasm")).is_equal("no-cache")
	assert_str(StaticServer.cache_control("index.0123456789.wasm")).contains("immutable")
	assert_str(StaticServer.cache_control("index.0123456789.audio.worklet.js")).contains(
		"immutable"
	)
	assert_str(StaticServer.cache_control("index.0123456789xy.wasm")).is_equal("no-cache")


# FT: FT-NET-039
func test_poll_writes_at_most_one_slice_per_connection() -> void:
	_server = StaticServer.new(_dir, 65536)
	var server: StaticServer = _server
	assert_int(server.listen(0, "127.0.0.1")).is_equal(OK)
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", server.local_port())
	var most: int = 0
	var got: int = 0
	var sent: bool = false
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and got < 300_000:
		var before: int = server.bytes_out
		server.poll(200)
		most = maxi(most, server.bytes_out - before)
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				tcp.put_data("GET /big.wasm HTTP/1.1\r\nHost: t\r\n\r\n".to_utf8_buffer())
				sent = true
			var n: int = tcp.get_available_bytes()
			if n > 0:
				got += (tcp.get_data(n)[1] as PackedByteArray).size()
	assert_int(got).is_greater(300_000)
	assert_int(most).is_less_equal(65536)


# FT: FT-NET-030
func test_head_responses_have_no_body() -> void:
	_server = StaticServer.new(_dir, 16384)
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
	# Three requests on one keep-alive connection: a body after either HEAD
	# response would show up in front of the next status line.
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _server.local_port())
	var request: String = (
		"HEAD /nope.js HTTP/1.1\r\nHost: t\r\n\r\n"
		+ "HEAD /index.html HTTP/1.1\r\nHost: t\r\n\r\n"
		+ "GET /index.html HTTP/1.1\r\nHost: t\r\n\r\n"
	)
	var raw: PackedByteArray = PackedByteArray()
	var sent: bool = false
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and not raw.get_string_from_ascii().ends_with("</p>"):
		_server.poll(400)
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				tcp.put_data(request.to_utf8_buffer())
				sent = true
			var n: int = tcp.get_available_bytes()
			if n > 0:
				raw.append_array(tcp.get_data(n)[1])
		OS.delay_usec(200)
	tcp.disconnect_from_host()
	var blocks: PackedStringArray = raw.get_string_from_ascii().split("\r\n\r\n")
	assert_int(blocks.size()).is_equal(4)
	assert_str(blocks[0]).starts_with("HTTP/1.1 404 ")
	assert_str(blocks[0]).contains("Content-Length: 10")
	assert_str(blocks[1]).starts_with("HTTP/1.1 200 ")
	assert_str(blocks[1]).contains("Content-Length: 9")
	assert_str(blocks[2]).starts_with("HTTP/1.1 200 ")
	assert_str(blocks[3]).is_equal("<p>hi</p>")


func test_listen_needs_an_explicit_address() -> void:
	_server = StaticServer.new(_dir)
	assert_int(_server.listen(0, "")).is_equal(ERR_INVALID_PARAMETER)
	assert_int(_server.listen(0, "*")).is_equal(ERR_INVALID_PARAMETER)
	assert_int(_server.local_port()).is_equal(0)
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
	assert_int(_server.local_port()).is_greater(0)


# FT: FT-NET-039
func test_poll_stops_when_the_budget_is_spent() -> void:
	_server = StaticServer.new(_dir, 65536)
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _server.local_port())
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_server.poll(0)
		tcp.poll()
		OS.delay_usec(200)
	tcp.put_data("GET /big.wasm HTTP/1.1\r\nHost: t\r\n\r\n".to_utf8_buffer())
	OS.delay_usec(20_000)
	# A spent budget services no connection: nothing is read or written.
	for i: int in range(20):
		_server.poll(0)
	assert_int(_server.open_connections()).is_equal(1)
	assert_int(_server.requests).is_equal(0)
	assert_int(_server.bytes_out).is_equal(0)
	# With a budget, the same request is answered.
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and _server.bytes_out == 0:
		_server.poll(StaticServer.DEFAULT_BUDGET_US)
		OS.delay_usec(200)
	assert_int(_server.requests).is_equal(1)
	assert_int(_server.bytes_out).is_greater(0)
	tcp.disconnect_from_host()


# FT: FT-NET-039
# The head search resumes where the last poll stopped and finds the blank line
# across reads, wherever it falls.
func test_header_end_resumes_from_the_scanned_offset() -> void:
	var req: PackedByteArray = "GET / HTTP/1.1\r\nHost: t\r\n\r\nNEXT".to_utf8_buffer()
	var end: int = StaticServer._header_end(req)
	assert_int(end).is_equal(req.size() - 8)
	for cut: int in range(1, req.size()):
		var first: PackedByteArray = req.slice(0, cut)
		var found: int = StaticServer._header_end(first)
		if found >= 0:
			assert_int(found).is_equal(end)
			continue
		assert_int(StaticServer._header_end(req, maxi(0, cut - 3))).is_equal(end)
	var lf: PackedByteArray = PackedByteArray()
	lf.resize(MAX_PROBE)
	lf.fill(10)
	assert_int(StaticServer._header_end(lf)).is_equal(-1)


# FT: FT-NET-039
# A peer that sends 8 KiB without ending its head (letters, then line feeds, the slow
# case of a byte loop) costs each poll only the bytes that arrived since the last: the
# search resumes where it stopped, so the whole 8 KiB is searched once in total, plus
# the 3-byte overlap per poll, never once per chunk. Counted, not timed, so a loaded
# host can't fail it; the 400 us budget itself is measured by
# tools/static_server_profile.gd (a manual check).
func test_headerless_8k_peer_is_searched_once() -> void:
	for fill: int in [65, 10]:
		_server = StaticServer.new(_dir)
		assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
		var tcp: StreamPeerTCP = StreamPeerTCP.new()
		tcp.connect_to_host("127.0.0.1", _server.local_port())
		var junk: PackedByteArray = PackedByteArray()
		junk.resize(1024)
		junk.fill(fill)
		var polls: int = 0
		var deadline: int = Time.get_ticks_msec() + 3000
		var chunks: int = 0
		while Time.get_ticks_msec() < deadline and _received() < 8 * 1024:
			tcp.poll()
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED and chunks < 8:
				tcp.put_data(junk)
				chunks += 1
			OS.delay_usec(2000)
			_server.poll(StaticServer.DEFAULT_BUDGET_US)
			polls += 1
		assert_int(chunks).is_equal(8)
		assert_int(_received()).is_equal(8 * 1024)
		# Every byte searched (at least once) ...
		assert_int(_server.bytes_scanned).is_greater_equal(8 * 1024)
		# ... and only once: a rescan per chunk would search 1 + 2 + ... + 8 KiB.
		assert_int(_server.bytes_scanned).is_less_equal(8 * 1024 + 3 * polls)
		assert_int(_server.open_connections()).is_equal(1)
		assert_int(_server.requests).is_equal(0)
		tcp.disconnect_from_host()
		_server.stop()


## Bytes the server holds from its one connection (0 before it has taken it).
func _received() -> int:
	return _server._conns[0].inbuf.size() if _server.open_connections() == 1 else 0
