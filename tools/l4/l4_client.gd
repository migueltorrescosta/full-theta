extends SceneTree
## L4 headless client (T048, FT-TST-011, FT-TST-014): a NetClient driven by an intent
## file, one step at a time, each with a timeout. Writes a JSON-lines log and exits 0
## when every step passed, 1 on the first failed step, 2 on a bad command line or
## intent file. tools/l4/run.sh starts these; the intent format is in tools/l4/README.md.
##
## godot --headless --path . -s res://tools/l4/l4_client.gd -- --url ws://HOST:PORT
##   --name c1 --intent PATH --log PATH [--token-file PATH] [--run-dir DIR] [--max-s 120]
##   [--set K=V ...] [--client net|ui]
## `--client ui` runs the real menu, lobby and station screens (L4Ui) instead of a bare
## NetClient: the ui_* steps play them, the other steps watch the client they poll.
##
## Log lines: {"ms", "ev", ...}; ev is start, step (n, line, verb, ok, why, ms_taken),
## welcome, catalogue, event, snap (tick, kin hash, gap), note, end (the summary).

enum Result { WAIT, DONE, FAIL }

## Seconds a step may take unless it says timeout=S (2 loaded cores; fail fast on a
## real error: rejections and closes fail at once, not at the timeout).
const DEFAULT_TIMEOUT_S: float = 15.0
## Two-character operators first, so ">=" is not read as ">".
const OPS: Array[String] = ["==", "!=", ">=", "<=", "~=", "!~", "=", ">", "<"]
## Keys of a step that are parameters, not matchers, in the expect_* steps.
const PARAMS: Array[String] = ["timeout", "type", "id", "for", "keep"]
const L4Ui = preload("res://tools/l4/l4_ui.gd")
const SECTION_NAMES: Dictionary = {
	StationViews.Section.STATUS: "status",
	StationViews.Section.HELM: "helm",
	StationViews.Section.ENGINEERING: "engineering",
	StationViews.Section.MOUNTS: "mounts",
}

var url: String = ""
var client_name: String = "c"
var intent_path: String = ""
var log_path: String = ""
var token_path: String = ""
var run_dir: String = ""
var max_s: float = 120.0
## --set K=V: $K in the intent file reads V.
var vars: Dictionary = {}
## --client ui: the real client UI.
var ui_mode: bool = false

var _client: NetClient = NetClient.new()
var _steps: Array[Dictionary] = []
var _i: int = 0
## Per-step scratch state, cleared when a step starts; "why" is the reason a waiting
## step gives if it times out.
var _st: Dictionary = {}
var _step_us: int = 0
var _start_us: int = 0
var _log: FileAccess
var _dirty: bool = false
## Every delivered event, in order; expect_event searches from _cursor.
var _events: Array[Dictionary] = []
var _cursor: int = 0
## Tick of the event expect_event matched last.
var _matched_tick: int = 0
## Command ids (from `command id=...`) -> seq.
var _seqs: Dictionary = {}
var _last_snaps: int = 0
var _last_snap_us: int = 0
var _max_gap_us: int = 0
var _mark_snaps: int = 0
var _was_welcomed: bool = false
## Welcomed and not since dropped or said Bye: a close now fails the run at once.
var _live: bool = false
## Set by drop, bye and host_stop until the next connect: the close that follows is
## expected, even though the client still reads as welcomed until it completes.
var _leaving: bool = false
## Set by host_spawn and orphan_rejoin; it owns and polls _client.
var _host: HostSession
## The real UI (--client ui), which polls its own client.
var _ui: L4Ui
var _code: int = -1


func _initialize() -> void:
	Engine.max_fps = 120
	_start_us = Time.get_ticks_usec()
	if not _parse_args(OS.get_cmdline_user_args()):
		_finish(2, "bad command line")
		return
	_client.name = client_name
	if ui_mode:
		# The UI does more per frame; 60 frames/s is a player's rate (2 loaded cores).
		Engine.max_fps = 60
		_ui = L4Ui.new(root, run_dir, client_name, token_path)
	var err: String = _load_intent()
	var unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_line(
		{"ev": "start", "name": client_name, "url": url, "intent": intent_path, "unix_ms": unix_ms}
	)
	if err != "":
		_finish(2, err)
		return
	_begin_step()


func _process(_delta: float) -> bool:
	if _code >= 0:
		return true
	if _ui != null:
		_follow_ui_client()
	elif _host != null:
		_host.poll()
	else:
		_client.poll()
	_observe()
	if _code < 0:
		_run_steps()
	if _code < 0 and Time.get_ticks_usec() - _start_us > int(max_s * 1e6):
		_finish(1, "client ran longer than --max-s %.0f" % max_s)
	if _dirty and _log != null:
		_log.flush()
		_dirty = false
	return _code >= 0


# --- Setup. ---


func _parse_args(args: PackedStringArray) -> bool:
	var i: int = 0
	while i + 1 < args.size():
		var v: String = args[i + 1]
		match args[i]:
			"--url":
				url = v
			"--name":
				client_name = v
			"--intent":
				intent_path = v
			"--log":
				log_path = v
			"--token-file":
				token_path = v
			"--run-dir":
				run_dir = v
			"--max-s":
				max_s = v.to_float()
			"--set":
				vars[v.get_slice("=", 0)] = v.get_slice("=", 1)
			"--client":
				ui_mode = v == "ui"
			_:
				push_error("l4_client: unknown argument %s" % args[i])
				return false
		i += 2
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	if run_dir == "" and log_path != "":
		run_dir = log_path.get_base_dir()
	return intent_path != "" and i == args.size()


## Reads the intent file: one step per line, `verb key=value ...`; # starts a comment.
func _load_intent() -> String:
	if not FileAccess.file_exists(intent_path):
		return "no intent file %s" % intent_path
	var n: int = 0
	for raw: String in FileAccess.get_file_as_string(intent_path).split("\n"):
		n += 1
		var text: String = raw.split("#", true, 1)[0].strip_edges()
		if text == "":
			continue
		text = text.replace("$RUN", run_dir).replace("$NAME", client_name)
		for k: String in vars:
			text = text.replace("$" + k, vars[k])
		var words: PackedStringArray = _tokens(text)
		var step: Dictionary = {"n": n, "line": text, "verb": words[0], "args": []}
		if not has_method("_do_" + words[0]):
			return "line %d: unknown step %s" % [n, words[0]]
		if words[0].begins_with("ui_") and not ui_mode:
			return "line %d: %s needs --client ui" % [n, words[0]]
		for w: String in words.slice(1):
			var m: Array = _matcher(w)
			if m.is_empty():
				return "line %d: %s is not key=value" % [n, w]
			step["args"].append(m)
		_steps.append(step)
	return ""


## Splits on spaces outside quotes and brackets, so `rotation=Vector3(0, 1, 0)` is one.
static func _tokens(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur: String = ""
	var depth: int = 0
	var quoted: bool = false
	for ch: String in text:
		if ch == '"':
			quoted = not quoted
		elif not quoted and ch in ["(", "[", "{"]:
			depth += 1
		elif not quoted and ch in [")", "]", "}"]:
			depth -= 1
		if ch in [" ", "\t"] and depth == 0 and not quoted:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


## [key, op, value] of `key<op>value`, or [] if the word has no operator.
static func _matcher(word: String) -> Array:
	for at: int in word.length():
		for op: String in OPS:
			if word.substr(at, op.length()) == op and at > 0:
				return [word.substr(0, at), op, _value(word.substr(at + op.length()))]
	return []


## Ints, floats, true/false/null, "quoted strings", JSON arrays and objects,
## Vector2/Vector3(...); anything else is a bare string.
static func _value(s: String) -> Variant:
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	match s:
		"true":
			return true
		"false":
			return false
		"null":
			return null
	if s.begins_with('"') and s.ends_with('"') and s.length() >= 2:
		return s.substr(1, s.length() - 2)
	if s.begins_with("[") or s.begins_with("{"):
		return JSON.parse_string(s)
	if s.begins_with("Vector2(") or s.begins_with("Vector3("):
		return str_to_var(s)
	return s


# --- The step loop. ---


func _begin_step() -> void:
	_st = {"why": ""}
	_step_us = Time.get_ticks_usec()


func _run_steps() -> void:
	# Several instant steps may finish in one frame.
	while _code < 0 and _i < _steps.size():
		var step: Dictionary = _steps[_i]
		var r: int = call("_do_" + step["verb"], step)
		var took_ms: int = (Time.get_ticks_usec() - _step_us) / 1000
		if r == Result.WAIT and took_ms > int(_num(step, "timeout", DEFAULT_TIMEOUT_S) * 1000.0):
			_st["why"] = "timeout after %d ms: %s" % [took_ms, _st["why"]]
			r = Result.FAIL
		if r == Result.WAIT:
			return
		var ok: bool = r == Result.DONE
		if ok:
			_st["why"] = ""
		var entry: Dictionary = {"ev": "step", "n": step["n"], "line": step["line"]}
		entry.merge({"verb": step["verb"], "ok": ok, "ms_taken": took_ms, "why": _st["why"]})
		_line(entry)
		if not ok:
			_finish(1, "line %d (%s): %s" % [step["n"], step["line"], _st["why"]])
			return
		_i += 1
		_begin_step()
	if _code < 0:
		_finish(0, "")


## Records what arrived this frame: events, Welcome, Catalogue, snapshot cadence.
func _observe() -> void:
	if _ui == null:
		for e: Dictionary in _client.take_events():
			_on_event(e)
	if _client.is_welcomed() and not _was_welcomed:
		_line({"ev": "welcome", "welcome": _client.welcome})
		_line({"ev": "catalogue", "catalogue": _client.catalogue})
		_save_token()
	_was_welcomed = _client.is_welcomed()
	if _client.is_welcomed() and not _leaving:
		_live = true
	elif _live and _client.state != NetClient.State.CONNECTING:
		_finish(1, "the server closed the connection (state %s)" % _client.state)
	var n: int = _client.stats["snapshots"]
	if n != _last_snaps:
		var now: int = Time.get_ticks_usec()
		var gap: int = now - _last_snap_us if _last_snap_us > 0 else 0
		_max_gap_us = maxi(_max_gap_us, gap)
		_last_snap_us = now
		_last_snaps = n
		var kin: Dictionary = _client.view.kin
		_line({"ev": "snap", "tick": _client.view.tick, "k": kin.hash(), "gap_ms": gap / 1000})


func _on_event(e: Dictionary) -> void:
	_events.append(e)
	_line({"ev": "event", "type": e["type"], "seq": e["seq"], "tick": e["tick"]}, e)


## UI mode: watch whichever client the menu or shell has now; the shell takes its
## events, so they reach the log through NetClient.event_received.
func _follow_ui_client() -> void:
	var c: NetClient = _ui.client()
	if c == null:
		return
	_client = c
	if not c.event_received.is_connected(_on_event):
		c.event_received.connect(_on_event)


func _finish(code: int, why: String) -> void:
	_code = code
	var summary: Dictionary = {"ev": "end", "ok": code == 0, "code": code, "why": why}
	(
		summary
		. merge(
			{
				"steps_done": _i,
				"steps": _steps.size(),
				"stats": _client.stats,
				"view_rejected": _client.view.rejected,
				"max_gap_ms": _max_gap_us / 1000,
			}
		)
	)
	_line(summary)
	if _log != null:
		_log.flush()
	if code != 0:
		printerr("l4_client %s: %s" % [client_name, why])
	quit(code)


# --- Logging and helpers. ---


func _line(d: Dictionary, extra: Dictionary = {}) -> void:
	if _log == null:
		return
	var out: Dictionary = {"ms": (Time.get_ticks_usec() - _start_us) / 1000}
	out.merge(d)
	if not extra.is_empty():
		out["payload"] = extra.get("payload", {})
	_log.store_line(JSON.stringify(out))
	_dirty = true


func _arg(step: Dictionary, key: String, default: Variant = null) -> Variant:
	for m: Array in step["args"]:
		if m[0] == key:
			return m[2]
	return default


func _num(step: Dictionary, key: String, default: float) -> float:
	var v: Variant = _arg(step, key, default)
	return float(v) if v is int or v is float else default


func _matchers(step: Dictionary) -> Array:
	return step["args"].filter(func(m: Array) -> bool: return not PARAMS.has(m[0]))


func _elapsed_s() -> float:
	return (Time.get_ticks_usec() - _step_us) / 1e6


func _fail(why: String) -> Result:
	_st["why"] = why
	return Result.FAIL


func _wait(why: String) -> Result:
	_st["why"] = why
	return Result.WAIT


## Follows a dotted path: dictionary keys (ints too), array indices, `size`; a name on
## an array of dictionaries maps over it (entries.id is every entry's id).
static func _get_path(root: Variant, path: String) -> Variant:
	var cur: Variant = root
	for seg: String in path.split("."):
		if seg == "size" and (cur is Array or cur is Dictionary or cur is String):
			cur = cur.size()
		elif cur is Dictionary:
			var d: Dictionary = cur
			cur = d.get(seg, d.get(seg.to_int(), null) if seg.is_valid_int() else null)
		elif cur is Array and seg.is_valid_int():
			var a: Array = cur
			var k: int = seg.to_int()
			cur = a[k] if k >= 0 and k < a.size() else null
		elif cur is Array:
			cur = (cur as Array).map(
				func(x: Variant) -> Variant:
					return (x as Dictionary).get(seg) if x is Dictionary else null
			)
		else:
			return null
	return cur


static func _eq(a: Variant, b: Variant) -> bool:
	var na: bool = a is int or a is float
	var nb: bool = b is int or b is float
	if na and nb:
		return absf(float(a) - float(b)) <= 1e-6
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for k: int in a.size():
			if not _eq(a[k], b[k]):
				return false
		return true
	if a is StringName or b is StringName:
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


static func _contains(a: Variant, b: Variant) -> bool:
	if a is Array:
		return (a as Array).any(func(x: Variant) -> bool: return _eq(x, b))
	if a is Dictionary:
		return (a as Dictionary).has(b)
	if a is String:
		return (a as String).contains(str(b))
	return false


static func _holds(actual: Variant, op: String, want: Variant) -> bool:
	match op:
		"=", "==":
			return _eq(actual, want)
		"!=":
			return not _eq(actual, want)
		"~=":
			return _contains(actual, want)
		"!~":
			return not _contains(actual, want)
	if not ((actual is int or actual is float) and (want is int or want is float)):
		return false
	match op:
		">=":
			return float(actual) >= float(want)
		"<=":
			return float(actual) <= float(want)
		">":
			return float(actual) > float(want)
	return float(actual) < float(want)


## "" if every matcher holds on root, else what didn't.
static func _check(root: Variant, matchers: Array) -> String:
	for m: Array in matchers:
		var actual: Variant = _get_path(root, m[0])
		if not _holds(actual, m[1], m[2]):
			return "%s is %s, want %s %s" % [m[0], JSON.stringify(actual), m[1], str(m[2])]
	return ""


## The client view as a plain dictionary: every NetViewState variable, blocks also by
## section name (blocks.helm.throttle_setpoint), and the client's stats.
func _view_root() -> Dictionary:
	var root: Dictionary = {}
	for p: Dictionary in _client.view.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			root[p["name"]] = _client.view.get(p["name"])
	var blocks: Dictionary = (root.get("blocks", {}) as Dictionary).duplicate()
	for kind: int in SECTION_NAMES:
		if blocks.has(kind):
			blocks[SECTION_NAMES[kind]] = blocks[kind]
	root["blocks"] = blocks
	root["stats"] = _client.stats
	root["state"] = NetClient.State.keys()[_client.state].to_lower()
	return root


## Index of the first event from `from` of `type` whose matchers hold, or -1.
func _find_event(from: int, type: String, matchers: Array) -> int:
	for k: int in range(from, _events.size()):
		var e: Dictionary = _events[k]
		if (type == "" or e["type"] == type) and _check(e, matchers) == "":
			return k
	return -1


func _path_file(name: String) -> String:
	return run_dir.path_join(name)


func _save_token() -> void:
	if token_path == "" or _host != null or _ui != null:  # HostSession and the menu do
		return
	var host: String = url.trim_prefix("ws://").get_slice(":", 0)
	var port: int = url.get_slice(":", 2).to_int()
	SessionTokenFile.make(_client.token, host, port, _client.host_secret).save(token_path)


# --- Steps: connection. ---


## connect [url=ws://...] [resume=true|false] [expect=welcomed|rejected]: Hello with
## the stored token (unless resume=false) and, if stored, the host secret.
func _do_connect(step: Dictionary) -> Result:
	if not _st.has("sent"):
		_st["sent"] = true
		url = str(_arg(step, "url", url))
		_client.token = ""
		var saved: SessionTokenFile = SessionTokenFile.load_from(token_path)
		if saved != null and _arg(step, "resume", true):
			_client.token = saved.token
			_client.host_secret = saved.host_secret
		_was_welcomed = false
		_leaving = false
		_live = false
		_line({"ev": "note", "msg": "connect %s token=%s" % [url, _client.token != ""]})
		if _client.connect_to(url) != OK:
			return _fail("connect_to %s failed" % url)
	var want: String = str(_arg(step, "expect", "welcomed"))
	match _client.state:
		NetClient.State.WELCOMED:
			return Result.DONE if want == "welcomed" else _fail("welcomed, want %s" % want)
		NetClient.State.REJECTED:
			if want == "rejected":
				return Result.DONE
			return _fail("rejected: %s" % _client.reject_reason)
		NetClient.State.CLOSED:
			return _fail("connection closed before Welcome")
	return _wait("no Welcome yet")


## reconnect: NetClient.resume() (same process, same token).
func _do_reconnect(_step: Dictionary) -> Result:
	if not _st.has("sent"):
		_st["sent"] = true
		_was_welcomed = false
		_leaving = false
		_live = false
		_client.resume()
	if _client.is_welcomed():
		return Result.DONE
	if _client.state == NetClient.State.CLOSED:
		return _fail("connection closed before Welcome")
	return _wait("no Welcome yet")


func _do_drop(_step: Dictionary) -> Result:
	_live = false
	_leaving = true
	_client.drop()
	return Result.DONE


func _do_bye(_step: Dictionary) -> Result:
	_live = false
	_leaving = true
	_client.bye("l4")
	return Result.DONE


## forget_token: remove the token file (a player who left for good).
func _do_forget_token(_step: Dictionary) -> Result:
	SessionTokenFile.remove(token_path)
	return Result.DONE


# --- Steps: lobby, claims, commands, pause requests. ---


## pick ship=S entry=E [expect=ok|REASON|none]: waits for the answer: a `picked` event
## (reason "" is ok) or a rejection naming a reason.
func _do_pick(step: Dictionary) -> Result:
	if not _st.has("from"):
		_st["from"] = _events.size()
		_client.pick(int(_arg(step, "ship", 0)), str(_arg(step, "entry", "")))
	return _await_answer(step)


## release [expect=ok|REASON|none]: back to the pick screen.
func _do_release(step: Dictionary) -> Result:
	if not _st.has("from"):
		_st["from"] = _events.size()
		_client.release_pick()
	return _await_answer(step)


func _await_answer(step: Dictionary) -> Result:
	var want: String = str(_arg(step, "expect", "ok"))
	if want == "none":
		return Result.DONE
	for k: int in range(_st["from"], _events.size()):
		var e: Dictionary = _events[k]
		if not e["type"] in ["picked", "command_rejected", "request_rejected"]:
			continue
		var reason: String = str((e["payload"] as Dictionary).get("reason", ""))
		var got: String = "ok" if reason == "" else reason
		_cursor = maxi(_cursor, k + 1)
		return Result.DONE if got == want else _fail("answer %s, want %s" % [got, want])
	return _wait("no answer")


## ready [value=true]: sends Ready; expect the outcome with expect_event.
func _do_ready(step: Dictionary) -> Result:
	_client.set_ready(bool(_arg(step, "value", true)))
	return Result.DONE


func _do_claim(step: Dictionary) -> Result:
	_client.claim(str(_arg(step, "item", "")))
	return Result.DONE


func _do_release_claim(step: Dictionary) -> Result:
	_client.release_claim(str(_arg(step, "item", "")))
	return Result.DONE


## command id=NAME kind=K field=value ...: every key but id and timeout goes into the
## command dictionary; floats need a decimal point (throttle=1.0).
func _do_command(step: Dictionary) -> Result:
	var cmd: Dictionary = {}
	for m: Array in step["args"]:
		if m[0] != "id" and m[0] != "timeout":
			cmd[m[0]] = m[2]
	var seq: int = _client.command(cmd)
	_seqs[str(_arg(step, "id", "last"))] = seq
	return Result.DONE


func _do_abandon(step: Dictionary) -> Result:
	_client.abandon(int(_arg(step, "ship", 0)))
	return Result.DONE


func _do_vote_abandon(step: Dictionary) -> Result:
	_client.vote_abandon(int(_arg(step, "ship", 0)), bool(_arg(step, "vote", true)))
	return Result.DONE


func _do_takeover(step: Dictionary) -> Result:
	_client.takeover(int(_arg(step, "ship", 0)), str(_arg(step, "entry", "")))
	return Result.DONE


# --- Steps: expectations. ---


## expect_welcome <matchers>: on the current connection's Welcome (resumed=true ...).
func _do_expect_welcome(step: Dictionary) -> Result:
	if not _client.is_welcomed():
		return _wait("not welcomed")
	var why: String = _check(_client.welcome, _matchers(step))
	return Result.DONE if why == "" else _fail(why)


## expect_catalogue <matchers>: waits until the latest Catalogue matches.
func _do_expect_catalogue(step: Dictionary) -> Result:
	var why: String = _check(_client.catalogue, _matchers(step))
	return Result.DONE if why == "" else _wait(why)


## expect_view <matchers>: waits until the snapshot view matches (kin.*, blocks.helm.*,
## contacts, seq, tick, full_count, stats.fulls, state, any NetViewState variable).
func _do_expect_view(step: Dictionary) -> Result:
	var why: String = _check(_view_root(), _matchers(step))
	return Result.DONE if why == "" else _wait(why)


## expect_event type=T <matchers on {seq, tick, type, payload}> [keep=true]: waits for
## a matching event after the cursor and moves the cursor past it (unless keep).
func _do_expect_event(step: Dictionary) -> Result:
	var k: int = _find_event(_cursor, str(_arg(step, "type", "")), _matchers(step))
	if k < 0:
		return _wait("no matching %s event" % _arg(step, "type", ""))
	if not _arg(step, "keep", false):
		_cursor = k + 1
	_matched_tick = int(_events[k]["tick"])
	return Result.DONE


## expect_no_event type=T for=S <matchers>: no matching event after the cursor for S s.
func _do_expect_no_event(step: Dictionary) -> Result:
	var k: int = _find_event(_cursor, str(_arg(step, "type", "")), _matchers(step))
	if k >= 0:
		return _fail("unexpected event %s" % JSON.stringify(_events[k]))
	if _elapsed_s() >= _num(step, "for", 1.0):
		return Result.DONE
	return Result.WAIT


## expect_rejected id=NAME [reason=R]: the command's CommandRejected arrives.
func _do_expect_rejected(step: Dictionary) -> Result:
	var seq: int = _seqs.get(str(_arg(step, "id", "last")), -1)
	var want: Variant = _arg(step, "reason")
	for e: Dictionary in _events:
		if e["type"] == "command_rejected" and int(e["payload"].get("seq", -1)) == seq:
			var reason: String = str(e["payload"].get("reason", ""))
			if want == null or reason == str(want):
				return Result.DONE
			return _fail("rejected with %s, want %s" % [reason, want])
	return _wait("no CommandRejected for seq %d" % seq)


## expect_accepted id=NAME [for=S]: no CommandRejected for the command within S s [1].
func _do_expect_accepted(step: Dictionary) -> Result:
	var seq: int = _seqs.get(str(_arg(step, "id", "last")), -1)
	for e: Dictionary in _events:
		if e["type"] == "command_rejected" and int(e["payload"].get("seq", -1)) == seq:
			return _fail("rejected: %s" % e["payload"].get("reason", ""))
	return Result.DONE if _elapsed_s() >= _num(step, "for", 1.0) else Result.WAIT


## expect_flowing [max_gap_ms=1000] [min_snapshots=1]: snapshots arrived since the last
## mark and none was more than max_gap_ms after the previous one.
func _do_expect_flowing(step: Dictionary) -> Result:
	var max_gap: float = _num(step, "max_gap_ms", 1000.0)
	var gap_now: int = (Time.get_ticks_usec() - _last_snap_us) / 1000
	if _max_gap_us / 1000 > max_gap or (_last_snap_us > 0 and gap_now > max_gap):
		return _fail("snapshot gap %d ms > %d ms" % [maxi(_max_gap_us / 1000, gap_now), max_gap])
	var since: int = _client.stats["snapshots"] - _mark_snaps
	if since < int(_num(step, "min_snapshots", 1.0)):
		return _wait("%d snapshots since the mark" % since)
	return Result.DONE


## expect_tick_still for=S: snapshots keep coming but the sim tick does not pass the
## view's tick or the last matched event's tick for S seconds (a paused universe,
## FT-NET-034; run it after expect_event type=pause).
func _do_expect_tick_still(step: Dictionary) -> Result:
	if not _st.has("tick"):
		# The pause event carries the tick the sim stopped at, and it may overtake the
		# snapshot of that tick (events and snapshots are queued separately).
		_st["tick"] = maxi(_client.view.tick, _matched_tick)
		_st["n0"] = _client.stats["snapshots"]
	if _client.view.tick > int(_st["tick"]):
		return _fail("tick moved from %d to %d" % [_st["tick"], _client.view.tick])
	if _elapsed_s() < _num(step, "for", 1.0):
		return Result.WAIT
	if _client.stats["snapshots"] == int(_st["n0"]):
		return _fail("no snapshots while paused")
	return Result.DONE


## expect_tick_moving [ticks=30]: the sim tick advances by at least that many ticks.
func _do_expect_tick_moving(step: Dictionary) -> Result:
	if not _st.has("tick"):
		_st["tick"] = _client.view.tick
	var moved: int = _client.view.tick - int(_st["tick"])
	if moved >= int(_num(step, "ticks", 30.0)):
		return Result.DONE
	return _wait("tick moved %d" % moved)


## mark: forget earlier events for expect_event and restart the snapshot-gap watch.
func _do_mark(_step: Dictionary) -> Result:
	_cursor = _events.size()
	_max_gap_us = 0
	_mark_snaps = _client.stats["snapshots"]
	return Result.DONE


# --- Steps: time and coordination through files in the run directory. ---


## wait s=S: keeps polling for S seconds.
func _do_wait(step: Dictionary) -> Result:
	return Result.DONE if _elapsed_s() >= _num(step, "s", 1.0) else Result.WAIT


## signal name=X [value=V]: creates sig.X (run.sh and other clients wait on it).
func _do_signal(step: Dictionary) -> Result:
	var f: FileAccess = FileAccess.open(_path_file("sig.%s" % _arg(step, "name")), FileAccess.WRITE)
	if f == null:
		return _fail("can't write sig.%s" % _arg(step, "name"))
	f.store_string(str(_arg(step, "value", client_name)))
	f.close()
	return Result.DONE


## await name=X: waits for sig.X (from run.sh or another client).
func _do_await(step: Dictionary) -> Result:
	if FileAccess.file_exists(_path_file("sig.%s" % _arg(step, "name"))):
		return Result.DONE
	return _wait("no sig.%s" % _arg(step, "name"))


## barrier name=X n=N: arrives at X and waits until N clients have.
func _do_barrier(step: Dictionary) -> Result:
	var prefix: String = "bar.%s." % _arg(step, "name")
	if not _st.has("arrived"):
		_st["arrived"] = true
		FileAccess.open(_path_file(prefix + client_name), FileAccess.WRITE).close()
	var n: int = 0
	for f: String in DirAccess.get_files_at(run_dir):
		if f.begins_with(prefix):
			n += 1
	if n >= int(_num(step, "n", 3.0)):
		return Result.DONE
	return _wait("%d of %d at barrier %s" % [n, int(_num(step, "n", 3.0)), _arg(step, "name")])


## note msg=...: a line in the log.
func _do_note(step: Dictionary) -> Result:
	_line({"ev": "note", "msg": str(_arg(step, "msg", ""))})
	return Result.DONE


## exit: ends the run here with the steps so far passed.
func _do_exit(_step: Dictionary) -> Result:
	_i = _steps.size() - 1
	return Result.DONE


# --- Steps: the host client (FT-NET-001, FT-NET-003, TECH-8), through HostSession. ---


## The HostSession takes over the client: it polls it and connects it itself.
func _adopt_host(host: HostSession) -> void:
	_host = host
	_client = host.client
	_host.token_file = token_path


## host_spawn pid_file=PATH [port=0] [grace=S] [publish=NAME] [args=[...]]:
## HostSession.host(): spawns this executable as a headless server child (secret through
## the environment, `args` appended to its flags), waits for its pid file, joins as the
## host and stores the token and secret. publish writes the server URL to sig.NAME for
## run.sh. With --client ui the menu takes the session over, as after its Host button,
## and the step waits for the shell.
func _do_host_spawn(step: Dictionary) -> Result:
	if _host == null:
		_adopt_host(HostSession.new(client_name))
		_host.launcher.pid_file = str(_arg(step, "pid_file", _path_file("server.pid.json")))
		var options: HostSession.Options = HostSession.Options.new("127.0.0.1")
		options.port = int(_arg(step, "port", 0))
		options.beacon = false
		if _arg(step, "grace") != null:
			options.grace_s = str(_arg(step, "grace")).to_float()
		options.extra_args = PackedStringArray(_arg(step, "args", []))
		if _host.host(options) != OK:
			return _fail("HostSession.host: %s" % _host.error)
		if _ui != null:
			_ui.menu.host_session = _host  # the menu polls it and opens the shell
		_line({"ev": "note", "msg": "spawned server pid %d" % _host.launcher.pid})
	if _host.state == HostSession.State.FAILED:
		return _fail("HostSession: %s" % _host.error)
	if not _host.is_joined() or (_ui != null and _ui.menu.shell == null):
		return _wait("host session %s" % HostSession.State.keys()[_host.state])
	url = "ws://%s:%d" % [_host.join_address(), _host.launcher.port]
	if _arg(step, "publish") != null:
		var f: FileAccess = FileAccess.open(
			_path_file("sig.%s" % _arg(step, "publish")), FileAccess.WRITE
		)
		f.store_string(url)
		f.close()
	return Result.DONE


## orphan_rejoin pid_file=PATH [expect=offer_rejoin]: a relaunched host's start:
## OrphanCheck must say `expect`; then HostSession.check_orphan answers REJOIN and
## rejoins with the stored token and host secret. Waits until joined.
func _do_orphan_rejoin(step: Dictionary) -> Result:
	var pid_file: String = str(_arg(step, "pid_file", _path_file("server.pid.json")))
	if _host == null:
		var check: OrphanCheck = OrphanCheck.inspect(pid_file, token_path)
		var action: String = OrphanCheck.Action.keys()[check.action].to_lower()
		var want: String = str(_arg(step, "expect", "offer_rejoin"))
		if action != want:
			return _wait("OrphanCheck says %s, want %s" % [action, want])
		_line({"ev": "note", "msg": "orphan check: %s" % action})
		if want != "offer_rejoin":
			return Result.DONE
		var rejoin: Callable = func(_c: OrphanCheck) -> HostSession.Answer:
			return HostSession.Answer.REJOIN
		var host: HostSession = HostSession.check_orphan(rejoin, pid_file, token_path)
		if host == null:
			return _fail("check_orphan returned no session")
		_adopt_host(host)
		_was_welcomed = false
		_leaving = false
	if _host.state == HostSession.State.FAILED:
		return _fail("HostSession: %s" % _host.error)
	if not _host.is_joined():
		return _wait("host session %s" % HostSession.State.keys()[_host.state])
	url = "ws://%s:%d" % [_host.join_address(), _host.launcher.port]
	return Result.DONE


## host_stop: the host leaves: HostSession.stop() says Bye and kills the server (its
## child or the adopted orphan); waits until the process is gone.
func _do_host_stop(_step: Dictionary) -> Result:
	if _host == null:
		return _fail("no host session")
	if not _st.has("pid"):
		_st["pid"] = _host.launcher.pid
		_st["child"] = not _host.launcher.adopted
		_live = false
		_leaving = true
		_host.stop()
	var pid: int = int(_st["pid"])
	var alive: bool = OrphanCheck.process_alive(pid)
	if alive and _st["child"]:
		alive = OS.is_process_running(pid)  # our own child: reaped, not a zombie
	if alive:
		return _wait("server pid %d still running" % pid)
	return Result.DONE


# --- Steps: the real client UI (--client ui, L4Ui). ---


## ui_join [url=ws://...]: types the address into the menu and presses Join; waits until
## the shell runs (welcomed).
func _do_ui_join(step: Dictionary) -> Result:
	if not _st.has("sent"):
		_st["sent"] = true
		url = str(_arg(step, "url", url))
		var why: String = _ui.join(url.trim_prefix("ws://"))
		if why != "":
			return _fail(why)
	if _ui.menu.shell != null:
		return Result.DONE
	return _wait("not joined: %s" % _ui.status())


## ui_pick entry=E [expect=ok|REASON|none]: presses the entry's pick button in the lobby
## (of the ship shown) and waits for the answer, like `pick`.
func _do_ui_pick(step: Dictionary) -> Result:
	if not _st.has("from"):
		var why: String = _ui.pick(str(_arg(step, "entry", "")))
		if why != "":
			return _wait(why)
		_st["from"] = _events.size()
	return _await_answer(step)


## ui_button name=N: waits for a visible, enabled button named N in the shell (Start,
## Vote, RunAgain) and presses it.
func _do_ui_button(step: Dictionary) -> Result:
	var why: String = _ui.press(null, str(_arg(step, "name", "")))
	return Result.DONE if why == "" else _wait(why)


## ui_press id=I, ui_hold id=I, ui_release id=I: the intent's KB/M binding pressed and
## released, pressed, or released, as input events into the station screen.
func _do_ui_press(step: Dictionary) -> Result:
	var r: Result = _do_ui_hold(step)
	return _do_ui_release(step) if r == Result.DONE else r


func _do_ui_hold(step: Dictionary) -> Result:
	var why: String = _ui.intent(str(_arg(step, "id", "")), true)
	return Result.DONE if why == "" else _wait(why)


func _do_ui_release(step: Dictionary) -> Result:
	var why: String = _ui.intent(str(_arg(step, "id", "")), false)
	return Result.DONE if why == "" else _wait(why)


## ui_expect <matchers>: waits until L4Ui.state() matches (shown, focused, selection.id,
## marks.contact, claims, contacts, started, card, run_over.outcome, ...).
func _do_ui_expect(step: Dictionary) -> Result:
	var why: String = _check(_ui.state(), _matchers(step))
	return Result.DONE if why == "" else _wait(why)
