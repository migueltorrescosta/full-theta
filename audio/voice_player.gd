class_name VoicePlayer
extends Node
## The client's voice output (spec §9, audio/README.md): takes voice_line events and VOICE
## parts, keeps the subtitles (SubtitleFeed, FT-AUD-010), queues lines on a VoiceBus driven
## by real time, and plays them through one AudioStreamPlayer per voice bus (VoiceBuses:
## NPC lines on Voice, computer lines on VoiceComputer with the robotic filter, FT-AUD-004).
## Lines with `local` true carry no audio on the wire: they play their prerendered file
## from `local_lines` (LocalLines), and a missing file leaves the subtitle only.
## Browser audio unlock is #7's.
##
## The station UI forwards each event from NetClient.take_events() to handle_event() and
## calls pump(client) every frame after client.poll().

## A subtitle to show: SubtitleFeed.add's entry.
signal subtitle(entry: Dictionary)

const EVENT_TYPE: String = "voice_line"

var bus: VoiceBus = VoiceBus.new()
var subtitles: SubtitleFeed = SubtitleFeed.new()
## Prerendered files for local lines, for the session language; null: subtitles only.
var local_lines: LocalLines = null
## Milliseconds; tests may swap it.
var clock: Callable = Time.get_ticks_msec
## Bus name (VoiceBuses.VOICE, VoiceBuses.COMPUTER) -> its AudioStreamPlayer.
var players: Dictionary = {}
## Set in _ready unless bus.sink was replaced before (tests).
var stream_sink: VoiceStreamSink


func _ready() -> void:
	VoiceBuses.ensure()
	for bus_name: String in [VoiceBuses.VOICE, VoiceBuses.COMPUTER]:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = bus_name + "Stream"
		p.bus = bus_name
		add_child(p)
		players[bus_name] = p
	if bus.sink.get_script() == VoiceSink:
		stream_sink = VoiceStreamSink.new(players)
		bus.sink = stream_sink


func _process(delta: float) -> void:
	bus.update(_now())
	if stream_sink != null:
		stream_sink.process(delta)


## Consumes a voice_line event ({"type", "payload", ...}); false for any other event.
func handle_event(event: Dictionary) -> bool:
	if event.get("type", "") != EVENT_TYPE:
		return false
	var payload: Dictionary = event.get("payload", {})
	var now: int = _now()
	subtitle.emit(subtitles.add(payload, now))
	if not (bool(payload.get("local", false)) and bool(payload.get("audio", true))):
		bus.offer(payload, now)
		return true
	var stream: AudioStream = null
	if local_lines != null:
		stream = local_lines.stream(str(payload.get("line", "")))
	if stream == null:
		var muted: Dictionary = payload.duplicate()
		muted["audio"] = false
		bus.offer(muted, now)
	elif bus.offer(payload, now):
		var length_ms: int = ceili(stream.get_length() * 1000.0)
		bus.add_local(int(payload.get("clip", -1)), stream, length_ms, now)
	return true


## One VOICE message {clip, rate, pcm, part, last}; part and last default to 0 and true.
func handle_voice(msg: Dictionary) -> void:
	bus.add_part(
		int(msg.get("clip", -1)),
		int(msg.get("part", 0)),
		int(msg.get("rate", 0)),
		msg.get("pcm", PackedByteArray()),
		bool(msg.get("last", true)),
		_now()
	)


## Drains the client's received voice parts into the bus.
func pump(client: NetClient) -> void:
	for msg: Dictionary in client.voice_clips:
		handle_voice(msg)
	client.voice_clips.clear()


func _now() -> int:
	return int(clock.call())
