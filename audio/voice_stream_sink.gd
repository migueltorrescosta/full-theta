class_name VoiceStreamSink
extends VoiceSink
## Plays VoiceBus output through one AudioStreamPlayer. Streamed lines feed an
## AudioStreamGenerator: pushed parts are queued as raw PCM and converted to frames as the
## generator has room, so consecutive parts play gaplessly. Local lines play their own
## AudioStream (Ogg Vorbis) from a position. The player's bus follows the line's role
## (VoiceBuses). Call process() every frame.

## PROVISIONAL: generator buffer; covers frame hitches, and is the latency before a fade.
const BUFFER_S: float = 0.25

var player: AudioStreamPlayer
## Frames handed to the generator so far.
var frames_pushed: int = 0

var _clip: int = -1
var _chunks: Array[Dictionary] = []  # {"pcm": PackedByteArray, "at": byte offset}
var _fade_total_ms: float = 0.0
var _fade_left_ms: float = 0.0


func _init(audio_player: AudioStreamPlayer) -> void:
	player = audio_player


func begin(clip: int, role: String, _rate: int) -> void:
	_clear()
	_clip = clip
	player.bus = VoiceBuses.bus_for(role)


func push(clip: int, pcm: PackedByteArray, rate: int, from_sample: int) -> void:
	if clip != _clip:
		return
	var gen: AudioStreamGenerator = player.stream as AudioStreamGenerator
	if gen == null or int(gen.mix_rate) != rate:
		player.stop()
		gen = AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = BUFFER_S
		player.stream = gen
	if not player.playing:
		player.play()
	_chunks.append({"pcm": pcm, "at": from_sample * 2})


func play_stream(clip: int, stream: Object, from_ms: int) -> void:
	if clip != _clip or not stream is AudioStream:
		return
	player.stream = stream
	player.play(from_ms / 1000.0)


func fade_out(clip: int, fade_ms: int) -> void:
	if clip == _clip:
		_fade_total_ms = maxf(fade_ms, 1.0)
		_fade_left_ms = _fade_total_ms


func stop(clip: int) -> void:
	if clip != _clip:
		return
	_clear()
	var pb: AudioStreamGeneratorPlayback = _playback()
	if pb != null:
		pb.clear_buffer()
	elif player.playing:
		player.stop()


## Bytes of PCM queued but not yet in the generator.
func pending_bytes() -> int:
	var n: int = 0
	for c: Dictionary in _chunks:
		n += (c["pcm"] as PackedByteArray).size() - int(c["at"])
	return n


## Applies the fade and moves queued PCM into the generator.
func process(delta: float) -> void:
	if _fade_total_ms > 0.0:
		_fade_left_ms = maxf(_fade_left_ms - delta * 1000.0, 0.0)
		player.volume_linear = _fade_left_ms / _fade_total_ms
	var pb: AudioStreamGeneratorPlayback = _playback()
	if pb == null:
		return
	var room: int = pb.get_frames_available()
	while room > 0 and not _chunks.is_empty():
		var c: Dictionary = _chunks[0]
		var pcm: PackedByteArray = c["pcm"]
		var at: int = c["at"]
		var count: int = mini(room, (pcm.size() - at) >> 1)
		var frames: PackedVector2Array = PackedVector2Array()
		frames.resize(count)
		for i: int in range(count):
			var v: float = pcm.decode_s16(at + 2 * i) / 32768.0
			frames[i] = Vector2(v, v)
		pb.push_buffer(frames)
		frames_pushed += count
		room -= count
		at += 2 * count
		if at + 1 >= pcm.size():
			_chunks.pop_front()
		else:
			c["at"] = at


func _playback() -> AudioStreamGeneratorPlayback:
	if not player.is_inside_tree() or not player.playing:
		return null
	return player.get_stream_playback() as AudioStreamGeneratorPlayback


func _clear() -> void:
	_chunks.clear()
	_fade_total_ms = 0.0
	_fade_left_ms = 0.0
	player.volume_linear = 1.0
