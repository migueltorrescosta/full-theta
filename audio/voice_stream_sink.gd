class_name VoiceStreamSink
extends VoiceSink
## Plays VoiceBus output through one AudioStreamPlayer per voice bus (VoiceBuses: `Voice`
## for NPC lines, `VoiceComputer` for computer lines, FT-AUD-004), so a line's role picks
## its player and a line on one bus never retargets, cuts or fades a line on the other.
## Streamed lines feed an AudioStreamGenerator: pushed parts are queued as raw PCM and
## converted to frames as the generator has room, so consecutive parts, and consecutive
## lines on one bus at one rate, play gaplessly; a finished line's buffered tail plays out
## before the next line on its bus. Local lines play their own AudioStream (Ogg Vorbis)
## from a position. Call process() every frame.
##
## played() reports what was really heard of a line (frames the generator consumed, or the
## stream's playback position, less the output latency), so a preempted line resumes where
## the listener heard it stop rather than where the bus clock says (FT-AUD-007).
## Limit: a line that needs another stream on the same bus (a local line after a streamed
## one, the reverse, or a streamed line at another sample rate) replaces the player's
## stream, dropping whatever of the previous line was still buffered: the few milliseconds
## the generator lags the bus clock, at most BUFFER_S.

## PROVISIONAL: generator buffer; covers frame hitches.
const BUFFER_S: float = 0.25

## Bus name -> _Channel.
var _channels: Dictionary = {}


## One bus's player and the line on it.
class _Channel:
	extends RefCounted
	var player: AudioStreamPlayer
	var clip: int = -1
	var chunks: Array[Dictionary] = []  # {"pcm": PackedByteArray, "at": byte offset}
	## Frames handed to the current generator playback so far.
	var frames_pushed: int = 0
	## Where `clip`'s audio starts in frames_pushed's count.
	var clip_start_frame: int = 0
	## The generator playback's capacity in frames; -1 until measured.
	var capacity: int = -1
	## A local line's start position, ms.
	var from_ms: int = 0
	var fade_total_ms: float = 0.0
	var fade_left_ms: float = 0.0

	func _init(audio_player: AudioStreamPlayer) -> void:
		player = audio_player

	func pending_frames() -> int:
		var n: int = 0
		for c: Dictionary in chunks:
			n += ((c["pcm"] as PackedByteArray).size() - int(c["at"])) >> 1
		return n

	func generator() -> AudioStreamGenerator:
		return player.stream as AudioStreamGenerator

	func playback() -> AudioStreamGeneratorPlayback:
		if not player.is_inside_tree() or not player.playing:
			return null
		return player.get_stream_playback() as AudioStreamGeneratorPlayback

	## Frames the generator has played: handed to it less what it still buffers.
	func consumed() -> int:
		var pb: AudioStreamGeneratorPlayback = playback()
		if pb == null or capacity < 0:
			return frames_pushed
		return frames_pushed - maxi(capacity - pb.get_frames_available(), 0)

	func reset_fade() -> void:
		fade_total_ms = 0.0
		fade_left_ms = 0.0
		player.volume_linear = 1.0


## `players`: bus name (VoiceBuses.VOICE, VoiceBuses.COMPUTER) -> its AudioStreamPlayer,
## whose bus is set to that name.
func _init(players: Dictionary) -> void:
	for bus_name: String in players:
		var p: AudioStreamPlayer = players[bus_name]
		p.bus = bus_name
		_channels[bus_name] = _Channel.new(p)


## The player lines of `role` play on.
func player_for(role: String) -> AudioStreamPlayer:
	return (_channels[VoiceBuses.bus_for(role)] as _Channel).player


func begin(clip: int, role: String, _rate: int) -> void:
	var ch: _Channel = _channels[VoiceBuses.bus_for(role)]
	# Any audio still queued here is a finished line's tail (stop() clears a stopped one's):
	# it plays out first, and this line starts after it.
	ch.clip = clip
	ch.clip_start_frame = ch.frames_pushed + ch.pending_frames()
	ch.reset_fade()


func push(clip: int, pcm: PackedByteArray, rate: int, from_sample: int) -> void:
	var ch: _Channel = _channel(clip)
	if ch == null:
		return
	var gen: AudioStreamGenerator = ch.generator()
	if gen == null or int(gen.mix_rate) != rate:
		ch.player.stop()
		gen = AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = BUFFER_S
		ch.player.stream = gen
		ch.chunks.clear()  # another line's tail at another rate (see the limit above)
		ch.frames_pushed = 0
		ch.clip_start_frame = 0
	if not ch.player.playing:
		ch.player.play()
		# A new, empty playback: count from it.
		ch.clip_start_frame -= ch.frames_pushed
		ch.frames_pushed = 0
		ch.capacity = -1
	ch.chunks.append({"pcm": pcm, "at": from_sample * 2})


func play_stream(clip: int, stream: Object, from_ms: int) -> void:
	var ch: _Channel = _channel(clip)
	if ch == null or not stream is AudioStream:
		return
	ch.chunks.clear()
	ch.player.stream = stream
	ch.from_ms = from_ms
	ch.player.play(from_ms / 1000.0)


func fade_out(clip: int, fade_ms: int) -> void:
	var ch: _Channel = _channel(clip)
	if ch != null:
		ch.fade_total_ms = maxf(fade_ms, 1.0)
		ch.fade_left_ms = ch.fade_total_ms


func stop(clip: int) -> void:
	var ch: _Channel = _channel(clip)
	if ch == null:
		return
	ch.clip = -1
	ch.chunks.clear()
	ch.reset_fade()
	var pb: AudioStreamGeneratorPlayback = ch.playback()
	if pb != null:
		# Cleared frames are never heard: count them out.
		ch.frames_pushed = ch.consumed()
		pb.clear_buffer()
	elif ch.player.playing:
		ch.player.stop()


## How much of `clip` was heard since its begin(): samples for a streamed line, ms for a
## local one; -1 when unknown.
func played(clip: int) -> int:
	var ch: _Channel = _channel(clip)
	if ch == null or not ch.player.playing:
		return -1
	var latency_s: float = AudioServer.get_output_latency()
	var gen: AudioStreamGenerator = ch.generator()
	if gen == null:
		var at_ms: int = floori((ch.player.get_playback_position() - latency_s) * 1000.0)
		return maxi(at_ms - ch.from_ms, 0)
	if ch.capacity < 0:
		return -1
	var latency: int = floori(latency_s * gen.mix_rate)
	return maxi(ch.consumed() - ch.clip_start_frame - latency, 0)


## Bytes of PCM queued but not yet in a generator, over both buses.
func pending_bytes() -> int:
	var n: int = 0
	for ch: _Channel in _channels.values():
		n += 2 * ch.pending_frames()
	return n


## Frames handed to the generators' current playbacks, over both buses.
func frames_pushed() -> int:
	var n: int = 0
	for ch: _Channel in _channels.values():
		n += ch.frames_pushed
	return n


## Applies fades and moves queued PCM into the generators.
func process(delta: float) -> void:
	for ch: _Channel in _channels.values():
		_process_channel(ch, delta)


func _process_channel(ch: _Channel, delta: float) -> void:
	if ch.fade_total_ms > 0.0:
		ch.fade_left_ms = maxf(ch.fade_left_ms - delta * 1000.0, 0.0)
		ch.player.volume_linear = ch.fade_left_ms / ch.fade_total_ms
	var pb: AudioStreamGeneratorPlayback = ch.playback()
	if pb == null:
		return
	if ch.capacity < 0 and ch.frames_pushed == 0:
		ch.capacity = pb.get_frames_available()  # empty, so all of it is room
	var room: int = pb.get_frames_available()
	while room > 0 and not ch.chunks.is_empty():
		var c: Dictionary = ch.chunks[0]
		var pcm: PackedByteArray = c["pcm"]
		var at: int = c["at"]
		var count: int = mini(room, (pcm.size() - at) >> 1)
		var frames: PackedVector2Array = PackedVector2Array()
		frames.resize(count)
		for i: int in range(count):
			var v: float = pcm.decode_s16(at + 2 * i) / 32768.0
			frames[i] = Vector2(v, v)
		pb.push_buffer(frames)
		ch.frames_pushed += count
		room -= count
		at += 2 * count
		if at + 1 >= pcm.size():
			ch.chunks.pop_front()
		else:
			c["at"] = at


func _channel(clip: int) -> _Channel:
	if clip < 0:
		return null
	for ch: _Channel in _channels.values():
		if ch.clip == clip:
			return ch
	return null
