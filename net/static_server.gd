class_name StaticServer
extends RefCounted
## Non-blocking static HTTP/1.1 server for the web export (FT-NET-030, FT-NET-039),
## promoted from spike S3 (docs/spikes/S3.md). The server polls it once per frame
## after the tick and the WebSocket pump, with a 400 µs budget (D108).
##
## GET and HEAD only, files from one flat folder. Prefers `<file>.gz` with
## `Content-Encoding: gzip` when the request accepts gzip. Sends an ETag with
## `Cache-Control: no-cache`, so a reload revalidates and gets 304. No byte
## ranges (#9 re-adds them, and video/mp4, if Safari's keep-awake video needs
## them). Keeps connections alive. `poll()` does bounded work: it stops once
## `budget_us` has passed, and each connection writes at most `slice` bytes
## per call, read from the file as it goes, so a 30 MB download never blocks
## the caller's loop. Budget and limits are provisional: see docs/protocol.md,
## Rates and limits.

## The per-frame budget D108 settles on, in microseconds.
const DEFAULT_BUDGET_US: int = 400
const MAX_REQUEST: int = 8192
const IDLE_US: int = 15_000_000
const MIME: Dictionary = {
	"html": "text/html; charset=utf-8",
	"js": "text/javascript; charset=utf-8",
	"mjs": "text/javascript; charset=utf-8",
	"wasm": "application/wasm",
	"pck": "application/octet-stream",
	"png": "image/png",
	"svg": "image/svg+xml",
	"ico": "image/x-icon",
	"json": "application/json",
	"webm": "video/webm",
	"txt": "text/plain; charset=utf-8",
}


class Conn:
	extends RefCounted
	var tcp: StreamPeerTCP
	var inbuf: PackedByteArray = PackedByteArray()
	## Bytes of inbuf already searched for the end of the head, so each poll scans
	## only what arrived since (FT-NET-039: an 8 KiB peer can't cost 8 KiB a frame).
	var scanned: int = 0
	var pending: PackedByteArray = PackedByteArray()
	var file: FileAccess
	var remaining: int = 0
	var writing: bool = false
	var keep_alive: bool = true
	var last_us: int = 0
	var target: String = ""


var root: String = ""
var slice: int = 65536
var requests: int = 0
var gzip_responses: int = 0
var not_modified: int = 0
var errors: int = 0
var bytes_out: int = 0
## When true, each response appends "<status> <path> <body bytes>" to `log`.
var keep_log: bool = false
var log: Array[String] = []

var _tcp: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []
var _turn: int = 0


func _init(folder: String, slice_bytes: int = 65536) -> void:
	root = folder.trim_suffix("/")
	slice = slice_bytes


## Listens on `bind`, the LAN address the host picks; there is no default, so
## the server never binds to every interface by accident. "*" (every
## interface) is refused: pass "0.0.0.0" or "::" explicitly if that is meant.
## Port 0 picks a free port; read it back with `local_port()`.
func listen(port: int, bind: String) -> Error:
	if bind == "" or bind == "*":
		return ERR_INVALID_PARAMETER
	return _tcp.listen(port, bind)


## The port listened on (useful after `listen(0, ...)`), or 0 when not listening.
func local_port() -> int:
	return _tcp.get_local_port() if _tcp.is_listening() else 0


func open_connections() -> int:
	return _conns.size()


func stop() -> void:
	for c: Conn in _conns:
		c.tcp.disconnect_from_host()
	_conns.clear()
	_tcp.stop()


## Accepts, reads and writes until `budget_us` has passed. Connections take
## turns at being first, so one big download doesn't starve the others.
func poll(budget_us: int) -> void:
	var start: int = Time.get_ticks_usec()
	while _tcp.is_connection_available():
		var c: Conn = Conn.new()
		c.tcp = _tcp.take_connection()
		c.tcp.set_no_delay(true)
		c.last_us = start
		_conns.append(c)
	var n: int = _conns.size()
	if n == 0:
		return
	_turn = (_turn + 1) % n
	var closed: Array[Conn] = []
	for k: int in range(n):
		if Time.get_ticks_usec() - start >= budget_us:
			break
		var c: Conn = _conns[(_turn + k) % n]
		if not _service(c, start):
			closed.append(c)
	for c: Conn in closed:
		c.tcp.disconnect_from_host()
		_conns.erase(c)


## Returns false when the connection should close.
func _service(c: Conn, now_us: int) -> bool:
	c.tcp.poll()
	if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var avail: int = c.tcp.get_available_bytes()
	if avail > 0:
		var got: Array = c.tcp.get_partial_data(avail)
		if got[0] != OK:
			return false
		c.inbuf.append_array(got[1])
		c.last_us = now_us
	# Checked while writing too, so a client sending during a long download
	# can't grow inbuf without bound.
	if c.inbuf.size() > MAX_REQUEST:
		return false
	if not c.writing:
		var end: int = _header_end(c.inbuf, c.scanned)
		if end < 0:
			c.scanned = maxi(0, c.inbuf.size() - 3)
			return now_us - c.last_us < IDLE_US
		var head: String = c.inbuf.slice(0, end).get_string_from_utf8()
		c.inbuf = c.inbuf.slice(end + 4)
		c.scanned = 0
		_respond(c, parse_request(head))
	if c.writing:
		c.last_us = now_us
		return _write(c)
	return true


## Writes up to `slice` bytes. Returns false when the connection should close.
func _write(c: Conn) -> bool:
	var budget: int = slice
	while budget > 0:
		if c.pending.is_empty():
			if c.remaining > 0:
				c.pending = c.file.get_buffer(mini(budget, c.remaining))
				if c.pending.is_empty():
					return false
				c.remaining -= c.pending.size()
			else:
				c.writing = false
				c.file = null
				return c.keep_alive
		var res: Array = c.tcp.put_partial_data(c.pending)
		if res[0] != OK:
			return false
		var sent: int = res[1]
		bytes_out += sent
		budget -= sent
		if sent < c.pending.size():
			c.pending = c.pending.slice(sent)
			return true
		c.pending = PackedByteArray()
	return true


func _respond(c: Conn, req: Dictionary) -> void:
	requests += 1
	var headers: Dictionary = req.get("headers", {})
	c.keep_alive = (
		req.get("version", "") == "HTTP/1.1"
		and String(headers.get("connection", "")).to_lower() != "close"
	)
	c.writing = true
	c.target = req.get("path", "?")
	if req.is_empty():
		_simple(c, 400, "Bad Request", true)
		c.keep_alive = false
		return
	var method: String = req["method"]
	if method != "GET" and method != "HEAD":
		_simple(c, 405, "Method Not Allowed", true, ["Allow: GET, HEAD"])
		return
	var is_get: bool = method == "GET"
	var name: String = resolve(req["path"])
	var path: String = root + "/" + name
	if name == "" or not FileAccess.file_exists(path):
		_simple(c, 404, "Not Found", is_get)
		return
	var gz: bool = (
		accepts_gzip(headers.get("accept-encoding", "")) and FileAccess.file_exists(path + ".gz")
	)
	var send_path: String = path + ".gz" if gz else path
	var file: FileAccess = FileAccess.open(send_path, FileAccess.READ)
	if file == null:
		_simple(c, 404, "Not Found", is_get)
		return
	var size: int = file.get_length()
	var etag: String = (
		'"%x-%x%s"' % [size, FileAccess.get_modified_time(send_path), "-gz" if gz else ""]
	)
	var out: Array[String] = [
		"Content-Type: " + mime_for(name),
		"ETag: " + etag,
		"Cache-Control: no-cache",
		"Vary: Accept-Encoding",
	]
	if headers.get("if-none-match", "") == etag:
		not_modified += 1
		_head(c, 304, "Not Modified", out, 0)
		return
	if gz:
		gzip_responses += 1
		out.append("Content-Encoding: gzip")
	out.append("Content-Length: %d" % size)
	_head(c, 200, "OK", out, size if is_get else 0)
	if is_get and size > 0:
		c.file = file
		c.remaining = size


## An error response. A HEAD response carries the GET headers but no body:
## a body would be read as the start of the next keep-alive response.
func _simple(
	c: Conn, status: int, reason: String, with_body: bool, extra: Array[String] = []
) -> void:
	errors += 1
	var body: PackedByteArray = (reason + "\n").to_utf8_buffer()
	var lines: Array[String] = [
		"Content-Type: text/plain; charset=utf-8", "Content-Length: %d" % body.size()
	]
	lines.append_array(extra)
	_head(c, status, reason, lines, body.size() if with_body else 0)
	if with_body:
		c.pending.append_array(body)


## Queues the status line and headers; `body_bytes`, the body this response
## sends, is only for the log.
func _head(c: Conn, status: int, reason: String, lines: Array[String], body_bytes: int) -> void:
	var text: String = "HTTP/1.1 %d %s\r\n" % [status, reason]
	for line: String in lines:
		text += line + "\r\n"
	text += "Connection: %s\r\n\r\n" % ("keep-alive" if c.keep_alive else "close")
	if keep_log:
		log.append("%d %s %d" % [status, c.target, body_bytes])
	c.pending = text.to_utf8_buffer()
	c.remaining = 0
	c.file = null


## Index of the blank line ending a request head ("\r\n\r\n") at or after `from`,
## or -1. A native search: about 50 us for 8 KiB on fugaku, whatever the bytes (a
## GDScript byte loop took 2.4 ms on 8 KiB of line feeds). A NUL byte ends one
## search early; the head is then found in a later poll, or the connection closes on
## MAX_REQUEST or IDLE_US.
static func _header_end(buf: PackedByteArray, from: int = 0) -> int:
	var at: int = buf.slice(from).get_string_from_ascii().find("\r\n\r\n")
	return from + at if at >= 0 else -1


## Parses a request head (without the blank line). Returns {} if malformed,
## else {"method", "path", "version", "headers"} with lower-case header names.
static func parse_request(head: String) -> Dictionary:
	var lines: PackedStringArray = head.split("\r\n")
	var parts: PackedStringArray = lines[0].split(" ")
	if parts.size() != 3 or not parts[2].begins_with("HTTP/1."):
		return {}
	var headers: Dictionary = {}
	for i: int in range(1, lines.size()):
		var colon: int = lines[i].find(":")
		if colon > 0:
			headers[lines[i].left(colon).strip_edges().to_lower()] = (
				lines[i].substr(colon + 1).strip_edges()
			)
	return {"method": parts[0], "path": parts[1], "version": parts[2], "headers": headers}


## Maps a request path to a file name in the root folder, or "" if it isn't
## one: no sub-folders, no dot files, query strings ignored, "/" is index.html.
static func resolve(path: String) -> String:
	var name: String = path.get_slice("?", 0).get_slice("#", 0).uri_decode().trim_prefix("/")
	if name == "":
		return "index.html"
	if name.contains("/") or name.contains("\\") or name.begins_with("."):
		return ""
	return name


static func mime_for(name: String) -> String:
	return MIME.get(name.get_extension().to_lower(), "application/octet-stream")


## True if an Accept-Encoding value accepts gzip (q=0 refuses it).
static func accepts_gzip(value: String) -> bool:
	for item: String in value.to_lower().split(","):
		var parts: PackedStringArray = item.strip_edges().split(";")
		if parts[0].strip_edges() == "gzip":
			for p: String in parts.slice(1):
				var kv: String = p.strip_edges().replace(" ", "")
				if kv.begins_with("q=") and kv.substr(2).to_float() == 0.0:
					return false
			return true
	return false
