class_name S9ViewState
extends RefCounted
## Client-side state of one view, rebuilt from S9Views snapshot messages.

var seq: int = -1
var tick: int = 0
var own: Dictionary = {}
var radar: Dictionary = {}
var near: Dictionary = {}
var proj: Dictionary = {}
## Deltas that arrived without a preceding full snapshot (must stay 0).
var out_of_order: int = 0


## Applies one message; returns false if it couldn't be applied.
func apply(data: PackedByteArray) -> bool:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	if buf.get_u8() != S9Views.MSG_SNAPSHOT:
		return false
	var is_full: bool = buf.get_u8() & 1 == 1
	var new_seq: int = buf.get_u32()
	if not is_full and (seq < 0 or new_seq != seq + 1):
		out_of_order += 1
		return false
	tick = buf.get_u32()
	buf.get_64()
	var n: int = buf.get_u8()
	for i: int in range(n):
		var kind: int = buf.get_u8()
		var size: int = buf.get_u16()
		var end: int = buf.get_position() + size
		match kind:
			S9Own.KIND_OWN, S9Own.KIND_ENG:
				S9Own.apply(own, kind, data.slice(buf.get_position(), end))
			S9Radar.KIND:
				S9Radar.apply(radar, buf, is_full, tick)
			S9Near.KIND:
				S9Near.apply(near, buf, is_full, tick)
			S9Proj.KIND:
				S9Proj.apply(proj, buf, is_full, tick)
		buf.seek(end)
	seq = new_seq
	return true
