extends GdUnitTestSuite
## ClipLibrary (content/voice/clip_library.gd) read from memory and from a prerender
## directory in the prerender's format (DIR/<lang>/<role>.pcm and .json).

const DIR: String = "user://test_clip_library"


func after_test() -> void:
	VoiceFixture._remove(DIR)


func _pcm(values: Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(values.size() * 2)
	for i: int in values.size():
		out.encode_s16(i * 2, values[i])
	return out


# FT: FT-AUD-018
func test_clips_from_memory() -> void:
	var lib: ClipLibrary = ClipLibrary.new()
	var clips: Dictionary = {"num:1": [0, 2], "seg:a:0": [2, 3]}
	lib.add_role("computer", 22050, "en_GB-cori-medium", clips, _pcm([1, 2, 3, 4, 5]))
	assert_bool(lib.has_role("computer")).is_true()
	assert_bool(lib.has_role("npc")).is_false()
	assert_bool(lib.has_clip("computer", "num:1")).is_true()
	assert_bool(lib.has_clip("npc", "num:1")).is_false()
	assert_bool(lib.clip("computer", "num:1")["pcm"] == _pcm([1, 2])).is_true()
	assert_bool(lib.clip("computer", "seg:a:0")["pcm"] == _pcm([3, 4, 5])).is_true()
	assert_int(lib.clip("computer", "seg:a:0")["rate"]).is_equal(22050)
	assert_dict(lib.clip("computer", "num:9")).is_empty()
	assert_int(lib.rate("computer")).is_equal(22050)
	assert_int(lib.rate("npc")).is_equal(0)
	assert_array(Array(lib.keys("computer"))).contains_exactly_in_any_order(["num:1", "seg:a:0"])


# FT: FT-AUD-018
# load_dir reads each role found for the language; a language with no files (pt_PT in a
# release) gives an empty library, and a bad index is skipped.
func test_clips_from_a_prerender_directory() -> void:
	var fx: VoiceFixture = VoiceFixture.new(DIR)
	fx.write("en")
	var lib: ClipLibrary = ClipLibrary.load_dir(DIR, "en")
	assert_str(lib.lang).is_equal("en")
	assert_bool(lib.has_role("computer")).is_true()
	assert_bool(lib.has_role("npc")).is_true()
	var key: String = "num:hundred"
	var clip: PackedByteArray = lib.clip("computer", key)["pcm"]
	assert_int(clip.size()).is_equal(VoiceFixture.CLIP_SAMPLES * 2)
	assert_str(fx.levels["en"]["computer"][clip.decode_s16(0)]).is_equal(key)
	assert_bool(lib.has_clip("computer", "line:computer.hull_critical")).is_false()
	assert_bool(lib.has_clip("npc", "seg:npc.hail_trader:0")).is_true()
	assert_bool(ClipLibrary.load_dir(DIR, "pt_PT").has_role("computer")).is_false()
	var f: FileAccess = FileAccess.open(DIR.path_join("en/npc.json"), FileAccess.WRITE)
	f.store_string("[1, 2]")
	f.close()
	var partial: ClipLibrary = ClipLibrary.load_dir(DIR, "en")
	assert_bool(partial.has_role("npc")).is_false()
	assert_bool(partial.has_role("computer")).is_true()
