class_name SessionLog
extends RefCounted
## The server's session log (D199, #9): a small append-only structured log, one JSON object
## per line (JSON Lines), kept for the whole session. Each line is
## `{"t": seconds since the log opened, "kind": "...", ...fields}`. It also keeps named
## counters, written as one `summary` line when the log closes, so a system that happens
## often (a request chip, a minigame move) counts instead of logging every occurrence.
##
## API, for every strand:
## - `SessionLog.open(path)` returns a log, or null when the file can't be created;
##   `SessionLog.default_path()` is `user://logs/session-<unix time>.jsonl`.
## - `event(kind, fields)` appends a line (`kind` is a short snake_case name; `fields`
##   must be JSON-friendly: numbers, strings, booleans, arrays, dictionaries).
## - `count(name, n = 1)` adds to a counter; `counters()` reads them.
## - `close(summary = {})` writes the `summary` line (counters plus `summary`) and closes.
## Writes are flushed at once; a crash loses at most the line being written.

var path: String = ""

var _file: FileAccess
var _start_us: int = 0
var _counters: Dictionary = {}


## Opens (creating folders) `path` for appending; null on failure.
static func open(log_path: String) -> SessionLog:
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var mode: FileAccess.ModeFlags = (
		FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE_READ
	)
	var file: FileAccess = FileAccess.open(log_path, mode)
	if file == null:
		return null
	file.seek_end()
	var log: SessionLog = SessionLog.new()
	log.path = log_path
	log._file = file
	log._start_us = Time.get_ticks_usec()
	return log


static func default_path() -> String:
	return "user://logs/session-%d.jsonl" % int(Time.get_unix_time_from_system())


func is_open() -> bool:
	return _file != null


func event(kind: String, fields: Dictionary = {}) -> void:
	if _file == null:
		return
	var line: Dictionary = {"t": snappedf((Time.get_ticks_usec() - _start_us) / 1e6, 0.001)}
	line["kind"] = kind
	line.merge(fields)
	_file.store_line(JSON.stringify(line))
	_file.flush()


func count(counter: String, n: int = 1) -> void:
	_counters[counter] = int(_counters.get(counter, 0)) + n


func counters() -> Dictionary:
	return _counters.duplicate()


## Writes the `summary` line and closes the file. Safe to call twice.
func close(summary: Dictionary = {}) -> void:
	if _file == null:
		return
	var fields: Dictionary = {"counters": _counters.duplicate()}
	fields.merge(summary)
	event("summary", fields)
	_file.close()
	_file = null
