extends SceneTree
## Voice latency harness, headless client (FT-AUD-015, the S7b method): a NetClient
## that stamps each VOICE message as it completes, then, after poll(), wraps each part
## in an AudioStreamWAV the way a player would. A headless client has no audio output,
## so that hand-off is "audible" (S7b). The target c0 gets every line; the bystander c1
## must get no voice bytes (FT-AUD-019).
##
## godot --headless --path . -s res://tools/voice_latency/vl_client.gd -- --url URL
##   --name c0 --log PATH [--run-for 900] [--max-fps 60]
##
## Log: one JSON object per line: welcome; line (a voice_line event: clip, audio, local,
## arrival_us); voice (clip, part, last, rate, bytes, audio_ms, arrival_us, handoff_us);
## summary (voice, voice_bytes, events). Times are unix µs.


## NetClient that records when each VOICE message is complete.
class StampedClient:
	extends NetClient

	func _on_message(stream: int, data: PackedByteArray) -> void:
		var n: int = voice_clips.size()
		super(stream, data)
		if voice_clips.size() > n:
			voice_clips[n]["arrival_us"] = int(Time.get_unix_time_from_system() * 1_000_000.0)


var url: String = ""
var client_name: String = "c0"
var log_path: String = ""
var run_for: float = 900.0
var max_fps: int = 60

var _client: StampedClient = StampedClient.new()
var _log: FileAccess
var _start_us: int = 0
var _welcomed: bool = false
var _counts: Dictionary = {"voice": 0, "voice_bytes": 0, "events": 0}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, args.size() - 1, 2):
		match args[i]:
			"--url":
				url = args[i + 1]
			"--name":
				client_name = args[i + 1]
			"--log":
				log_path = args[i + 1]
			"--run-for":
				run_for = args[i + 1].to_float()
			"--max-fps":
				max_fps = args[i + 1].to_int()
	Engine.max_fps = max_fps
	_start_us = Time.get_ticks_usec()
	_log = FileAccess.open(log_path, FileAccess.WRITE)
	_client.name = client_name
	if url == "" or _log == null or _client.connect_to(url) != OK:
		push_error("vl_client: needs --url and --log, and a server to connect to")
		quit(2)


func _process(_delta: float) -> bool:
	_client.poll()
	if _client.is_welcomed() and not _welcomed:
		_welcomed = true
		_line({"ev": "welcome", "session": _client.session_id})
	for e: Dictionary in _client.take_events():
		_counts["events"] += 1
		if e["type"] == VoiceService.EVENT_VOICE_LINE:
			var p: Dictionary = e["payload"]
			_line(
				{
					"ev": "line",
					"clip": p["clip"],
					"audio": p["audio"],
					"local": p["local"],
					"arrival_us": _unix_us()
				}
			)
	for m: Dictionary in _client.voice_clips:
		_hand_off(m)
	_client.voice_clips.clear()
	var closed: bool = _client.state in [NetClient.State.CLOSED, NetClient.State.REJECTED]
	if closed or (Time.get_ticks_usec() - _start_us) / 1_000_000.0 > run_for:
		_counts["ev"] = "summary"
		_line(_counts)
		_log.close()
		return true
	return false


## The part as an AudioStreamWAV an AudioStreamPlayer (or the VoiceStreamSink's
## generator) could start at once: the S7b "audible" point.
func _hand_off(m: Dictionary) -> void:
	var pcm: PackedByteArray = m["pcm"]
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = m["rate"]
	wav.stereo = false
	wav.data = pcm
	var handoff_us: int = _unix_us()
	_counts["voice"] += 1
	_counts["voice_bytes"] += pcm.size()
	_line(
		{
			"ev": "voice",
			"clip": m["clip"],
			"part": m["part"],
			"last": m["last"],
			"rate": m["rate"],
			"bytes": pcm.size(),
			"audio_ms": wav.get_length() * 1000.0,
			"arrival_us": m.get("arrival_us", handoff_us),
			"handoff_us": handoff_us,
		}
	)


func _line(fields: Dictionary) -> void:
	_log.store_line(JSON.stringify(fields))
	_log.flush()


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)
