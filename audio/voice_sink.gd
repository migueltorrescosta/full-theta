class_name VoiceSink
extends RefCounted
## Where VoiceBus sends audio (FT-AUD-011): the bus decides, a sink plays. This base
## does nothing; VoiceStreamSink plays on the Voice buses and tests use a recording stub.
## Audio pushed for a line is contiguous: each push follows the previous one with no gap.


## A line starts (or resumes) on this sink; `role` picks the bus ("computer" or "npc").
func begin(_clip: int, _role: String, _rate: int) -> void:
	pass


## Appends `pcm` (16-bit mono little endian) from sample `from_sample` on.
func push(_clip: int, _pcm: PackedByteArray, _rate: int, _from_sample: int) -> void:
	pass


## Plays a local line's stream (an AudioStream) from `from_ms` on.
func play_stream(_clip: int, _stream: Object, _from_ms: int) -> void:
	pass


## Fades the line to silence over `fade_ms`; stop() follows when the fade ends.
func fade_out(_clip: int, _fade_ms: int) -> void:
	pass


## Stops the line at once and drops its buffered audio (after a fade, or a stalled line).
func stop(_clip: int) -> void:
	pass


## The line has no more audio: play out what is buffered, then fall silent.
func finish(_clip: int) -> void:
	pass


## How much of the line was heard since its begin(), in the units of its positions
## (samples for streamed parts, ms for a local stream); -1 when the sink can't tell, and
## the bus goes by its clock (FT-AUD-007).
func played(_clip: int) -> int:
	return -1
