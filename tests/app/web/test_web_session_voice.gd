extends GdUnitTestSuite
## The browser station fetches its session language's voice pack from next to the page
## (WebSession.voice_pack_url, D294).


# FT: FT-AUD-013
func test_voice_pack_url_sits_next_to_the_page() -> void:
	var cases: Array = [
		["http://192.168.1.20:47800/", "en", "http://192.168.1.20:47800/voice-en.pack"],
		[
			"https://fugaku.ts.net:47800/index.html?pick=helm#x",
			"it",
			"https://fugaku.ts.net:47800/voice-it.pack"
		],
		["http://[::1]:47800/?join=0", "pt_PT", "http://[::1]:47800/voice-pt_PT.pack"],
		["http://host/sub/dir/page.html", "en", "http://host/sub/dir/voice-en.pack"],
	]
	for c: Array in cases:
		assert_str(WebSession.voice_pack_url(c[0], c[1])).is_equal(c[2])
