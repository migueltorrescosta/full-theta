extends VoiceSink
## A VoiceSink for tests: records every call as [name, clip, ...], plays nothing.
var calls: Array[Array] = []
## What played() reports for every clip; -1: unknown, the bus goes by its clock.
var heard: int = -1


func begin(clip: int, role: String, rate: int) -> void:
	calls.append(["begin", clip, role, rate])


func push(clip: int, pcm: PackedByteArray, _rate: int, from_sample: int) -> void:
	calls.append(["push", clip, pcm.size() >> 1, from_sample])


func play_stream(clip: int, _stream: Object, from_ms: int) -> void:
	calls.append(["stream", clip, from_ms])


func fade_out(clip: int, fade_ms: int) -> void:
	calls.append(["fade", clip, fade_ms])


func stop(clip: int) -> void:
	calls.append(["stop", clip])


func finish(clip: int) -> void:
	calls.append(["finish", clip])


func played(_clip: int) -> int:
	return heard


func named(call_name: String) -> Array[Array]:
	var out: Array[Array] = []
	for c: Array in calls:
		if c[0] == call_name:
			out.append(c)
	return out
