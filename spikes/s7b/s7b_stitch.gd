class_name S7bStitch
extends RefCounted
## Trims and joins 16-bit mono PCM clips (D101 stitching, as in S7): silence
## below 2 % of full scale is cut to 10 ms of padding, and fragments are joined
## with a fixed gap. Pure functions, no audio output.

const THRESHOLD: int = 655
const GAP_MS: int = 70


## Returns pcm without leading and trailing silence, keeping 10 ms of padding.
static func trim(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var samples: int = pcm.size() / 2
	var first: int = 0
	while first < samples and absi(pcm.decode_s16(first * 2)) <= THRESHOLD:
		first += 1
	if first == samples:
		return PackedByteArray()
	var last: int = samples - 1
	while absi(pcm.decode_s16(last * 2)) <= THRESHOLD:
		last -= 1
	var pad: int = rate / 100
	first = maxi(0, first - pad)
	last = mini(samples - 1, last + pad)
	return pcm.slice(first * 2, (last + 1) * 2)


## Joins clips with gap_ms of silence between them.
static func join(parts: Array[PackedByteArray], rate: int, gap_ms: int = GAP_MS) -> PackedByteArray:
	var gap: PackedByteArray = PackedByteArray()
	gap.resize(rate * gap_ms / 1000 * 2)
	gap.fill(0)
	var out: PackedByteArray = PackedByteArray()
	for i: int in range(parts.size()):
		if i > 0:
			out.append_array(gap)
		out.append_array(parts[i])
	return out
