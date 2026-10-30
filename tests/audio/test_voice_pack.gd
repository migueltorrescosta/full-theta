extends GdUnitTestSuite
## Per-language voice packs for the web export (audio/voice_pack.gd, D294): parsing, the
## clip spans, malformed packs, and LocalLines playing a line from its language's pack.


## A pack whose streams need no Ogg decoding (the repo has no clip fixture).
class StubPack:
	extends VoicePack

	func stream(line_id: String) -> AudioStream:
		return AudioStreamGenerator.new() if has(line_id) else null


func after_test() -> void:
	LocalLines.clear_packs()


## A pack as tools/release/voice_pack.py writes it.
static func _pack(
	lang: String, clips: Dictionary, version: int = VoicePack.VERSION
) -> PackedByteArray:
	var spans: Dictionary = {}
	var data: PackedByteArray = PackedByteArray()
	for line: String in clips:
		var blob: PackedByteArray = (clips[line] as String).to_utf8_buffer()
		spans[line] = [data.size(), blob.size()]
		data.append_array(blob)
	var header: PackedByteArray = (
		JSON.stringify({"language": lang, "clips": spans}).to_utf8_buffer()
	)
	var out: PackedByteArray = VoicePack.MAGIC.to_ascii_buffer()
	out.resize(VoicePack.HEAD)
	out.encode_u32(4, version)
	out.encode_u32(8, header.size())
	out.append_array(header)
	out.append_array(data)
	return out


# FT: FT-AUD-002, FT-AUD-013
func test_parses_a_pack_and_slices_each_clip() -> void:
	var p: VoicePack = VoicePack.parse(
		_pack("it", {"npc.hail": "OggS-one", "computer.jump_ready": "OggS-two!"})
	)
	assert_object(p).is_not_null()
	assert_str(p.language).is_equal("it")
	assert_int(p.size()).is_equal(2)
	assert_bool(p.has("npc.hail")).is_true()
	assert_str(p.clip("npc.hail").get_string_from_utf8()).is_equal("OggS-one")
	assert_str(p.clip("computer.jump_ready").get_string_from_utf8()).is_equal("OggS-two!")
	assert_bool(p.has("npc.other")).is_false()
	assert_int(p.clip("npc.other").size()).is_equal(0)
	assert_object(p.stream("npc.other")).is_null()


# FT: FT-AUD-002
func test_rejects_malformed_packs() -> void:
	var good: PackedByteArray = _pack("en", {"npc.hail": "OggS"})
	var bad_magic: PackedByteArray = good.duplicate()
	bad_magic[0] = 0x58
	var truncated: PackedByteArray = good.slice(0, good.size() - 1)
	for data: PackedByteArray in [
		PackedByteArray(),
		good.slice(0, 8),
		bad_magic,
		truncated,
		_pack("en", {"npc.hail": "OggS"}, 2),
	]:
		assert_object(VoicePack.parse(data)).is_null()
	assert_object(VoicePack.parse(good)).is_not_null()


# FT: FT-AUD-013
func test_local_lines_play_from_their_languages_pack_once_it_arrives() -> void:
	var lines: LocalLines = LocalLines.new("en", "res://tests/audio/no_such_dir")
	assert_object(lines.stream("npc.hail")).is_null()
	var it: StubPack = StubPack.new()
	it.language = "it"
	it._clips["npc.hail"] = [0, 1]
	LocalLines.add_pack(it)
	# Another language's pack doesn't play.
	assert_object(lines.stream("npc.hail")).is_null()
	var en: StubPack = StubPack.new()
	en.language = "en"
	en._clips["npc.hail"] = [0, 1]
	LocalLines.add_pack(en)
	assert_bool(LocalLines.has_pack("en")).is_true()
	# A miss before the pack came isn't cached; a reconnect's new LocalLines plays too.
	assert_object(lines.stream("npc.hail")).is_not_null()
	(
		assert_object(LocalLines.new("en", "res://tests/audio/no_such_dir").stream("npc.hail"))
		. is_not_null()
	)
	assert_object(lines.stream("npc.missing")).is_null()
