extends GdUnitTestSuite
## SubtitleFeed: every voice_line becomes a subtitle at once, with its role label.


func _payload(clip: int, text: String, role: String = "npc", audio: bool = true) -> Dictionary:
	return {
		"clip": clip,
		"line": "npc.hail",
		"text": text,
		"role": role,
		"priority": 2,
		"max_age_ms": 1000,
		"coalesce": "",
		"resume": false,
		"audio": audio
	}


# FT: FT-AUD-010
func test_line_shows_at_once_with_role_label() -> void:
	var feed: SubtitleFeed = SubtitleFeed.new()
	var e: Dictionary = feed.add(_payload(7, "Shields holding.", "computer"), 1000)
	assert_str(e["text"]).is_equal("Shields holding.")
	assert_str(e["label_key"]).is_equal("subtitle.computer")
	assert_int(e["shown_ms"]).is_equal(1000)
	assert_array(feed.active(1000)).is_equal([e])
	assert_str(feed.add(_payload(8, "Hello."), 1000)["label_key"]).is_equal("subtitle.npc")


# FT: FT-AUD-010
func test_subtitle_shows_even_without_audio() -> void:
	var feed: SubtitleFeed = SubtitleFeed.new()
	feed.add(_payload(1, "Free text over the limit.", "npc", false), 0)
	assert_array(feed.active(0)).has_size(1)


# FT: FT-AUD-010
func test_subtitles_expire_by_text_length() -> void:
	var feed: SubtitleFeed = SubtitleFeed.new()
	var short: Dictionary = feed.add(_payload(1, "Hi."), 0)
	var long: Dictionary = feed.add(_payload(2, "x".repeat(60)), 0)
	assert_int(short["expires_ms"]).is_equal(SubtitleFeed.duration_ms("Hi."))
	assert_int(long["expires_ms"]).is_greater(short["expires_ms"])
	assert_int(SubtitleFeed.duration_ms("x".repeat(1000))).is_equal(SubtitleFeed.MAX_MS)
	assert_array(feed.active(short["expires_ms"])).is_equal([long])
	assert_array(feed.active(long["expires_ms"])).is_empty()


# FT: FT-AUD-010
func test_keeps_only_the_latest_subtitles() -> void:
	var feed: SubtitleFeed = SubtitleFeed.new()
	for i: int in range(SubtitleFeed.KEEP + 2):
		feed.add(_payload(i, "Line %d" % i), i)
	var active: Array[Dictionary] = feed.active(100)
	assert_array(active).has_size(SubtitleFeed.KEEP)
	assert_int(active[0]["clip"]).is_equal(2)
