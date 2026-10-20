# FT: FT-NET-031, FT-GEN-013
extends GdUnitTestSuite
## T047: LAN only, no internet play, relay or master server (FT-NET-031,
## FT-GEN-013). A static scan of the project's GDScript (addons/, spikes/, tests/
## and .godot/ excluded) with comments stripped. It is a tripwire, not a proof:
## - HTTPClient or HTTPRequest (outgoing HTTP) only in the static HTTP server;
## - no string URL (scheme://host) or IPv4 literal naming a public host;
## - no relay, master-server, matchmaking, NAT punch-through or STUN/TURN code.

const SKIP_DIRS: Array[String] = ["addons", "spikes", "tests", ".godot", ".git", "build"]
## The static HTTP server may name HTTPClient for its status constants.
const HTTP_ALLOWED: String = "static_server"
const INTERNET_WORDS: String = (
	"(?i)(master|relay|rendezvous)[_ ]?server|matchmak|nat[_ ]?punch|hole[_ ]?punch"
	+ "|\\b(stun|turn)s?:"
)


func _scripts(dir: String, out: Array[String]) -> void:
	for d: String in DirAccess.get_directories_at(dir):
		if dir == "res://" and d in SKIP_DIRS:
			continue
		_scripts(dir.path_join(d), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


## Splits GDScript into code (comments dropped, strings blanked) and its strings.
static func _split(text: String) -> Array[String]:
	var code: String = ""
	var strings: String = ""
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var c: String = text[i]
		if c == "#":
			while i < n and text[i] != "\n":
				i += 1
		elif c == '"' or c == "'":
			var q: String = text.substr(i, 3) if text.substr(i, 3) in ['"""', "'''"] else c
			var start: int = i + q.length()
			i = start
			while i < n and text.substr(i, q.length()) != q:
				i += 2 if text[i] == "\\" else 1
			strings += text.substr(start, i - start) + "\n"
			code += " "
			i += q.length()
		else:
			code += c
			i += 1
	return [code, strings]


## Findings for one file's text, as "what" lines.
static func _check(path: String, text: String) -> Array[String]:
	var found: Array[String] = []
	var parts: Array[String] = _split(text)
	var http: RegEx = RegEx.create_from_string("\\bHTTP(Client|Request)\\b")
	if http.search(parts[0]) != null and not path.contains(HTTP_ALLOWED):
		found.append("%s: outgoing HTTP (%s)" % [path, http.search(parts[0]).get_string()])
	var words: RegEx = RegEx.create_from_string(INTERNET_WORDS)
	for m: RegExMatch in words.search_all(parts[0] + "\n" + parts[1]):
		found.append("%s: internet service code (%s)" % [path, m.get_string()])
	var url: RegEx = RegEx.create_from_string(
		"(?i)\\b([a-z][a-z0-9+.-]*)://(\\[[^\\]]*\\]|[^/:\\s\"']*)"
	)
	for m: RegExMatch in url.search_all(parts[1]):
		var scheme: String = m.get_string(1).to_lower()
		if scheme in ["res", "user", "uid"]:
			continue
		if not _is_lan_host(m.get_string(2).trim_prefix("[").trim_suffix("]")):
			found.append("%s: public URL (%s)" % [path, m.get_string()])
	var ip: RegEx = RegEx.create_from_string("\\b\\d{1,3}(\\.\\d{1,3}){3}\\b")
	for m: RegExMatch in ip.search_all(parts[1]):
		if not _is_lan_host(m.get_string()):
			found.append("%s: public address (%s)" % [path, m.get_string()])
	return found


## Loopback, private, link-local, CGNAT, broadcast and unspecified IPv4; IPv6
## loopback, link-local and unique-local; .local/.lan names, bare names without a
## dot, placeholders (%s, HOST) and empty hosts.
static func _is_lan_host(h: String) -> bool:
	h = h.to_lower()
	if h.is_empty() or h == "localhost" or h.contains("%") or not h.contains("."):
		return not (h.contains(":") and not _is_lan_v6(h))
	if h.ends_with(".local") or h.ends_with(".lan"):
		return true
	var o: PackedStringArray = h.split(".")
	if o.size() != 4 or not h.is_valid_ip_address():
		return false
	var a: int = o[0].to_int()
	var b: int = o[1].to_int()
	return (
		a in [0, 10, 127]
		or h == "255.255.255.255"
		or (a == 172 and b >= 16 and b <= 31)
		or (a == 192 and b == 168)
		or (a == 169 and b == 254)
		or (a == 100 and b >= 64 and b <= 127)
	)


static func _is_lan_v6(h: String) -> bool:
	return h == "::1" or h == "::" or h.begins_with("fe80:") or h.begins_with("fd")


func test_project_has_no_internet_play_code() -> void:
	var files: Array[String] = []
	_scripts("res://", files)
	assert_int(files.size()).is_greater(10)
	var found: Array[String] = []
	for f: String in files:
		found.append_array(_check(f, FileAccess.get_file_as_string(f)))
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


## The scan catches what it claims to (a check that can't fail proves nothing).
func test_scanner_catches_planted_violations() -> void:
	var bad: Dictionary[String, String] = {
		"http": "var c: HTTPRequest = HTTPRequest.new()\n",
		"master": "func register_with_master_server() -> void:\n\tpass\n",
		"relay": 'const R: String = "relay server"\n',
		"url": 'const U: String = "wss://lobby.example.com/play"\n',
		"v6": 'const U6: String = "ws://[2001:4860::8888]:80"\n',
		"ip": 'const IPS: String = "8.8.8.8"\n',
		"stun": 'const S: String = "stun:stun.l.google.com:19302"\n',
	}
	for k: String in bad:
		var found: Array[String] = _check("res://net/x.gd", bad[k])
		assert_array(found).override_failure_message(k).is_not_empty()
	var good: String = (
		"# relay_server and https://example.com in a comment\n"
		+ 'const A: String = "ws://192.168.1.20:47800"\n'
		+ 'const B: String = "ws://[::1]:47800"\n'
		+ 'const C: String = "ws://%s:%d"\n'
		+ 'const D: String = "255.255.255.255"\n'
		+ 'const E: String = "relay"\n'
		+ "var c: HTTPClient\n"
	)
	var found_good: Array[String] = _check("res://net/x.gd", good)
	assert_array(found_good).is_equal(["res://net/x.gd: outgoing HTTP (HTTPClient)"])
	assert_array(_check("res://net/static_server.gd", good)).is_empty()
