extends GdUnitTestSuite
## Optional HTTPS and WSS with brotli (D294, load fix 12): the --tls-cert/--tls-key flags,
## the static server's brotli preference and TLS, and the WebSocket transport over TLS.
## One self-signed certificate for the suite (RSA key generation takes a moment).

static var _key: CryptoKey
static var _cert: X509Certificate

var _dir: String = ""
var _server: StaticServer
var _transport: NetTransport


func before() -> void:
	var crypto: Crypto = Crypto.new()
	_key = crypto.generate_rsa(2048)
	_cert = crypto.generate_self_signed_certificate(_key, "CN=localhost,O=Full Theta,C=PT")


func before_test() -> void:
	_dir = ProjectSettings.globalize_path("user://static_tls_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	_write("index.wasm", "plain")
	_write("index.wasm.gz", "gzipped")
	_write("index.wasm.br", "brotli")
	_write("index.html", "<p>hi</p>")


func after_test() -> void:
	if _server != null:
		_server.stop()
		_server = null
	if _transport != null:
		_transport.stop()
		_transport = null
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _write(name: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join(name), FileAccess.WRITE)
	f.store_buffer(text.to_utf8_buffer())
	f.close()


func _start(tls: TLSOptions) -> StaticServer:
	_server = StaticServer.new(_dir)
	_server.tls = tls
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
	return _server


## One GET for `path` with `accept` as Accept-Encoding, over TLS when `tls` is set;
## returns {"status", "headers", "body"} or {} on a timeout.
func _fetch(path: String, accept: String, tls: TLSOptions = null) -> Dictionary:
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _server.local_port())
	var peer: StreamPeer = tcp
	var stream: StreamPeerTLS = null
	var request: String = (
		"GET %s HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: %s\r\nConnection: close\r\n\r\n"
		% [path, accept]
	)
	var raw: PackedByteArray = PackedByteArray()
	var sent: bool = false
	var deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		_server.poll(2000)
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			OS.delay_usec(200)
			continue
		if tls != null and stream == null:
			stream = StreamPeerTLS.new()
			assert_int(stream.connect_to_stream(tcp, "localhost", tls)).is_equal(OK)
			peer = stream
		if stream != null:
			stream.poll()
			if stream.get_status() == StreamPeerTLS.STATUS_HANDSHAKING:
				continue
			if stream.get_status() != StreamPeerTLS.STATUS_CONNECTED:
				break
		if not sent:
			peer.put_data(request.to_utf8_buffer())
			sent = true
		var n: int = peer.get_available_bytes()
		if n > 0:
			raw.append_array(peer.get_data(n)[1])
			var res: Dictionary = _parse(raw)
			if not res.is_empty():
				return res
		OS.delay_usec(200)
	return {}


static func _parse(raw: PackedByteArray) -> Dictionary:
	var text: String = raw.get_string_from_utf8()
	var end: int = text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines: PackedStringArray = text.left(end).split("\r\n")
	var headers: Dictionary = {}
	for line: String in lines.slice(1):
		headers[line.get_slice(":", 0).to_lower()] = line.substr(line.find(":") + 1).strip_edges()
	var length: int = int(headers.get("content-length", "0"))
	if raw.size() < end + 4 + length:
		return {}
	return {
		"status": int(lines[0].get_slice(" ", 1)),
		"headers": headers,
		"body": raw.slice(end + 4, end + 4 + length).get_string_from_utf8(),
	}


# FT: FT-NET-030
func test_accept_encoding_parsing() -> void:
	assert_bool(StaticServer.accepts("gzip, deflate, br, zstd", "br")).is_true()
	assert_bool(StaticServer.accepts("gzip, br;q=0", "br")).is_false()
	assert_bool(StaticServer.accepts("gzip", "br")).is_false()
	assert_bool(StaticServer.accepts("BR;q=0.5", "br")).is_true()
	assert_bool(StaticServer.accepts_gzip("br, gzip")).is_true()


# FT: FT-NET-030
func test_prefers_brotli_then_gzip_then_the_file() -> void:
	_start(null)
	var br: Dictionary = _fetch("/index.wasm", "gzip, deflate, br")
	assert_str(br["body"]).is_equal("brotli")
	assert_str(br["headers"]["content-encoding"]).is_equal("br")
	assert_str(br["headers"]["vary"]).is_equal("Accept-Encoding")
	var gz: Dictionary = _fetch("/index.wasm", "gzip, br;q=0")
	assert_str(gz["body"]).is_equal("gzipped")
	assert_str(gz["headers"]["content-encoding"]).is_equal("gzip")
	assert_str(br["headers"]["etag"]).is_not_equal(gz["headers"]["etag"])
	var plain: Dictionary = _fetch("/index.wasm", "identity")
	assert_str(plain["body"]).is_equal("plain")
	assert_bool(plain["headers"].has("content-encoding")).is_false()
	# No .br copy: gzip, as before.
	_write("index.html.gz", "html-gz")
	assert_str(_fetch("/index.html", "br, gzip")["body"]).is_equal("html-gz")
	assert_int(_server.brotli_responses).is_equal(1)
	assert_int(_server.gzip_responses).is_equal(2)


# FT: FT-NET-030
func test_serves_https_with_the_given_certificate() -> void:
	_start(TLSOptions.server(_key, _cert))
	var res: Dictionary = _fetch("/index.wasm", "br", TLSOptions.client(_cert))
	assert_int(res.get("status", 0)).is_equal(200)
	assert_str(res["body"]).is_equal("brotli")
	# A plain-HTTP request to the HTTPS server gets no HTTP answer.
	assert_dict(_fetch("/index.wasm", "br")).is_empty()


# FT: FT-NET-030
func test_websocket_transport_speaks_wss() -> void:
	_transport = NetTransport.new()
	_transport.tls = TLSOptions.server(_key, _cert)
	assert_int(_transport.start(0, "127.0.0.1")).is_equal(OK)
	var ws: WebSocketPeer = WebSocketPeer.new()
	var url: String = "wss://127.0.0.1:%d" % _transport.port()
	assert_int(ws.connect_to_url(url, TLSOptions.client_unsafe(_cert))).is_equal(OK)
	var deadline: int = Time.get_ticks_msec() + 5000
	while (
		Time.get_ticks_msec() < deadline and ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING
	):
		ws.poll()
		OS.delay_msec(5)
	assert_int(ws.get_ready_state()).is_equal(WebSocketPeer.STATE_OPEN)
	ws.close()


# FT: FT-NET-002
func test_tls_flags_go_together_and_need_absolute_paths() -> void:
	var cli: ServerMain = ServerMain.new()
	var both: PackedStringArray = [
		"--bind", "127.0.0.1", "--tls-cert", "/srv/c.pem", "--tls-key", "/srv/k.pem"
	]
	assert_bool(cli.parse_args(both)).is_true()
	assert_str(cli.tls_cert).is_equal("/srv/c.pem")
	assert_str(cli.tls_key).is_equal("/srv/k.pem")
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--tls-cert", "/c.pem"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--tls-key", "/k.pem"])).is_false()
	var relative: PackedStringArray = ["--bind", "::1", "--tls-cert", "c.pem", "--tls-key", "/k"]
	assert_bool(ServerMain.new().parse_args(relative)).is_false()
	var plain: ServerMain = ServerMain.new()
	assert_bool(plain.parse_args(["--bind", "127.0.0.1"])).is_true()
	assert_str(plain.tls_cert).is_empty()


# FT: FT-NET-030
func test_loads_pem_files_and_reports_missing_ones() -> void:
	var cert_path: String = _dir.path_join("cert.pem")
	var key_path: String = _dir.path_join("key.pem")
	assert_int(_cert.save(cert_path)).is_equal(OK)
	assert_int(_key.save(key_path)).is_equal(OK)
	assert_object(ServerMain.load_tls(cert_path, key_path)).is_not_null()
	assert_object(ServerMain.load_tls(_dir.path_join("none.pem"), key_path)).is_null()


# FT: FT-NET-030
# An HTTPS page can't open ws:// (mixed content), so the client upgrades the socket URL
# to wss:// on such a page; elsewhere the URL is unchanged.
func test_socket_url_follows_the_page_scheme() -> void:
	assert_str(NetClient.socket_url("ws://10.0.0.2:47821", "https:")).is_equal(
		"wss://10.0.0.2:47821"
	)
	assert_str(NetClient.socket_url("ws://10.0.0.2:47821", "http:")).is_equal("ws://10.0.0.2:47821")
	assert_str(NetClient.socket_url("ws://10.0.0.2:47821", "")).is_equal("ws://10.0.0.2:47821")
	assert_str(NetClient.socket_url("wss://h:1", "https:")).is_equal("wss://h:1")
