extends GdUnitTestSuite
## S7b spike: trimming and joining of cached clips (spike evidence for D101
## stitching; the ids stay pending until E10 promotes the code).


func _pcm(values: Array[int]) -> PackedByteArray:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(values.size() * 2)
	for i: int in range(values.size()):
		pcm.encode_s16(i * 2, values[i])
	return pcm


func _silence(samples: int) -> Array[int]:
	var out: Array[int] = []
	out.resize(samples)
	out.fill(10)
	return out


func test_trim_keeps_ten_ms_padding() -> void:
	# Rate 1000 Hz: 10 ms of padding is 10 samples.
	var values: Array[int] = _silence(50)
	values.append_array([2000, -3000, 1000])
	values.append_array(_silence(40))
	var trimmed: PackedByteArray = S7bStitch.trim(_pcm(values), 1000)
	assert_int(trimmed.size() / 2).is_equal(10 + 3 + 10)
	assert_int(trimmed.decode_s16(10 * 2)).is_equal(2000)
	assert_int(trimmed.decode_s16(12 * 2)).is_equal(1000)


func test_trim_padding_stops_at_the_edges() -> void:
	var trimmed: PackedByteArray = S7bStitch.trim(_pcm([5000, 0, 0, -5000]), 1000)
	assert_int(trimmed.size() / 2).is_equal(4)


func test_trim_silence_is_empty() -> void:
	assert_int(S7bStitch.trim(_pcm(_silence(100)), 22050).size()).is_equal(0)


func test_join_inserts_gaps_between_parts() -> void:
	var parts: Array[PackedByteArray] = [_pcm([1, 2]), _pcm([3]), _pcm([4])]
	var joined: PackedByteArray = S7bStitch.join(parts, 1000, 5)
	assert_int(joined.size() / 2).is_equal(4 + 2 * 5)
	assert_int(joined.decode_s16(2 * 2)).is_equal(0)
	assert_int(joined.decode_s16(7 * 2)).is_equal(3)
	assert_int(joined.decode_s16(13 * 2)).is_equal(4)
