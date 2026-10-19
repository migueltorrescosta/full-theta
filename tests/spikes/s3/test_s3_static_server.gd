extends GdUnitTestSuite
## S3 spike: the static HTTP server (spike evidence for FT-NET-030 and
## FT-NET-039; the ids stay pending until #6 promotes the code).

const PORT: int = 47829

var _dir: String = ""


func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://s3_static_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	var body: PackedByteArray = PackedByteArray()
	body.resize(300_000)
	for i: int in range(body.size()):
		body[i] = i % 251
	_write(_dir + "/big.wasm", body)
	_write(_dir + "/big.wasm.gz", "pretend-gzip".to_utf8_buffer())
	_write(_dir + "/index.html", "<p>hi</p>".to_utf8_buffer())


func after_test() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	DirAccess.remove_absolute(_dir)


func _write(path: String, data: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


## Sends one request and polls server and client until the response is in.
## Returns {"status": int, "headers": Dictionary, "body": PackedByteArray}.
func _fetch(server: S3StaticServer, request: String) -> Dictionary:
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", PORT)
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
	var req: Dictionary = S3StaticServer.parse_request(
		"GET /index.wasm?v=2 HTTP/1.1\r\nHost: x\r\nAccept-Encoding: gzip, br"
	)
	assert_str(req["method"]).is_equal("GET")
	assert_str(req["path"]).is_equal("/index.wasm?v=2")
	assert_str(req["headers"]["accept-encoding"]).is_equal("gzip, br")
	assert_bool(S3StaticServer.parse_request("nonsense").is_empty()).is_true()


func test_resolve_stays_in_the_folder() -> void:
	assert_str(S3StaticServer.resolve("/")).is_equal("index.html")
	assert_str(S3StaticServer.resolve("/?name=a")).is_equal("index.html")
	assert_str(S3StaticServer.resolve("/index.pck?x")).is_equal("index.pck")
	assert_str(S3StaticServer.resolve("/../project.godot")).is_equal("")
	assert_str(S3StaticServer.resolve("/%2e%2e/x")).is_equal("")
	assert_str(S3StaticServer.resolve("/a/b.js")).is_equal("")
	assert_str(S3StaticServer.resolve("/.env")).is_equal("")


func test_mime_types() -> void:
	assert_str(S3StaticServer.mime_for("index.wasm")).is_equal("application/wasm")
	assert_str(S3StaticServer.mime_for("index.js")).starts_with("text/javascript")
	assert_str(S3StaticServer.mime_for("index.html")).starts_with("text/html")
	assert_str(S3StaticServer.mime_for("keepawake.webm")).is_equal("video/webm")
	assert_str(S3StaticServer.mime_for("index.pck")).is_equal("application/octet-stream")


func test_accepts_gzip() -> void:
	assert_bool(S3StaticServer.accepts_gzip("gzip, deflate, br")).is_true()
	assert_bool(S3StaticServer.accepts_gzip("br;q=1.0, gzip;q=0.8")).is_true()
	assert_bool(S3StaticServer.accepts_gzip("gzip;q=0")).is_false()
	assert_bool(S3StaticServer.accepts_gzip("identity")).is_false()
	assert_bool(S3StaticServer.accepts_gzip("")).is_false()


func test_parse_range() -> void:
	assert_object(S3StaticServer.parse_range("bytes=0-99", 1000)).is_equal(Vector2i(0, 99))
	assert_object(S3StaticServer.parse_range("bytes=900-", 1000)).is_equal(Vector2i(900, 999))
	assert_object(S3StaticServer.parse_range("bytes=-100", 1000)).is_equal(Vector2i(900, 999))
	assert_object(S3StaticServer.parse_range("bytes=0-5000", 1000)).is_equal(Vector2i(0, 999))
	assert_object(S3StaticServer.parse_range("bytes=1000-", 1000)).is_equal(Vector2i(-1, -1))
	assert_object(S3StaticServer.parse_range("bytes=0-1,5-6", 1000)).is_equal(Vector2i(-1, -1))
	assert_object(S3StaticServer.parse_range("", 1000)).is_equal(Vector2i(-1, -1))


func test_serves_gzip_etag_and_ranges_over_loopback() -> void:
	var server: S3StaticServer = S3StaticServer.new(_dir, 16384)
	assert_int(server.listen(PORT, "127.0.0.1")).is_equal(OK)
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
	var part: Dictionary = _fetch(
		server, "GET /big.wasm HTTP/1.1\r\nHost: t\r\nRange: bytes=10-19\r\n\r\n"
	)
	assert_int(part["status"]).is_equal(206)
	assert_str(part["headers"]["content-range"]).is_equal("bytes 10-19/300000")
	assert_int((part["body"] as PackedByteArray)[0]).is_equal(10)
	var missing: Dictionary = _fetch(server, "GET /nope.js HTTP/1.1\r\nHost: t\r\n\r\n")
	assert_int(missing["status"]).is_equal(404)
	var post: Dictionary = _fetch(server, "POST / HTTP/1.1\r\nHost: t\r\n\r\n")
	assert_int(post["status"]).is_equal(405)
	server.stop()


func test_poll_writes_at_most_one_slice_per_connection() -> void:
	var server: S3StaticServer = S3StaticServer.new(_dir, 65536)
	assert_int(server.listen(PORT, "127.0.0.1")).is_equal(OK)
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", PORT)
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
	server.stop()
	assert_int(got).is_greater(300_000)
	assert_int(most).is_less_equal(65536)
