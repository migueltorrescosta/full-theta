class_name PcmStitch
extends RefCounted
## Trims, normalises and joins 16-bit mono little-endian PCM (D101 stitching, promoted
## from spike S7b): silence below 2 % of full scale is cut to 10 ms of padding, as the
## prerender does for segments and number fragments (tools/tts/prerender.py), and
## stitched pieces are joined with a fixed gap. Pure functions, no audio output.

## 2 % of full scale.
const THRESHOLD: int = 655
## Gap between stitched pieces (S7). PROVISIONAL.
const GAP_MS: int = 70
## Peak a normalised clip reaches, as a fraction of full scale (as the prerender).
const PEAK: float = 0.9


## Returns pcm without leading and trailing silence, keeping 10 ms of padding; empty
## when the clip is silent.
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


## Scales pcm so its loudest sample reaches PEAK of full scale (silence stays silent).
static func normalise(pcm: PackedByteArray) -> PackedByteArray:
	var samples: int = pcm.size() / 2
	var peak: int = 0
	for i: int in samples:
		peak = maxi(peak, absi(pcm.decode_s16(i * 2)))
	if peak == 0:
		return pcm
	var gain: float = PEAK * 32767.0 / peak
	var out: PackedByteArray = PackedByteArray()
	out.resize(samples * 2)
	for i: int in samples:
		out.encode_s16(i * 2, clampi(roundi(pcm.decode_s16(i * 2) * gain), -32768, 32767))
	return out


## Joins clips with gap_ms of silence between them; empty clips are skipped.
static func join(parts: Array[PackedByteArray], rate: int, gap_ms: int = GAP_MS) -> PackedByteArray:
	var gap: PackedByteArray = PackedByteArray()
	gap.resize(rate * gap_ms / 1000 * 2)
	gap.fill(0)
	var out: PackedByteArray = PackedByteArray()
	for part: PackedByteArray in parts:
		if part.is_empty():
			continue
		if not out.is_empty():
			out.append_array(gap)
		out.append_array(part)
	return out
