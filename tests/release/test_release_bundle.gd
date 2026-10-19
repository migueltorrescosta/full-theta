extends GdUnitTestSuite
## Package layout lookups (ReleaseBundle, BundledPiper) and the L6 smoke flags
## (ReleaseSmoke). The exported builds themselves run in `gate.sh l6`.


# FT: FT-ARC-022
func test_web_and_resources_folder_per_platform() -> void:
	assert_str(ReleaseBundle.resources_dir_for("/opt/ft/full-theta.x86_64", false)).is_equal(
		"/opt/ft"
	)
	(
		assert_str(
			ReleaseBundle.resources_dir_for("/A/Full Theta.app/Contents/MacOS/Full Theta", true)
		)
		. is_equal("/A/Full Theta.app/Contents/Resources")
	)


# FT: FT-ARC-022
func test_piper_paths_per_platform() -> void:
	var lin: Dictionary = BundledPiper.paths_for("/opt/ft/full-theta.x86_64", "Linux")
	assert_str(lin["program"]).is_equal("/opt/ft/piper/piper")
	assert_str(lin["data"]).is_equal("/opt/ft/piper/espeak-ng-data")
	assert_str(lin["voices"]).is_equal("/opt/ft/piper/voices")
	var win: Dictionary = BundledPiper.paths_for("C:/ft/full-theta.exe", "Windows")
	assert_str(win["program"]).is_equal("C:/ft/piper/piper.exe")
	var mac: Dictionary = BundledPiper.paths_for("/A/F.app/Contents/MacOS/F", "macOS")
	assert_str(mac["program"]).is_equal("/A/F.app/Contents/Helpers/piper/piper")
	assert_str(mac["data"]).is_equal("/A/F.app/Contents/Resources/piper/espeak-ng-data")
	assert_str(mac["voices"]).is_equal("/A/F.app/Contents/Resources/piper/voices")
	assert_str(BundledPiper.paths_for("", "Linux")["program"]).is_equal("")


# FT: FT-ARC-022
func test_piper_command_names_model_and_espeak_data() -> void:
	var p: Dictionary = BundledPiper.paths_for("/opt/ft/full-theta.x86_64", "Linux")
	var cmd: PackedStringArray = BundledPiper.command(p, "en_GB-cori-medium", "/tmp")
	(
		assert_array(Array(cmd))
		. contains_exactly(
			[
				"--model",
				"/opt/ft/piper/voices/en_GB-cori-medium/en_GB-cori-medium.onnx",
				"--espeak_data",
				"/opt/ft/piper/espeak-ng-data",
				"--output_dir",
				"/tmp",
				"--quiet",
			]
		)
	)


# FT: FT-TST-019
func test_checkout_has_dev_build_info_and_no_bundle() -> void:
	assert_str(ReleaseBundle.build_line()).is_equal("build: dev dev")
	assert_str(ReleaseBundle.web_root()).is_equal("")
	assert_array(Array(BundledPiper.voices())).is_empty()


# FT: FT-TST-019
func test_smoke_flags() -> void:
	assert_bool(ReleaseSmoke.handles(["--tts-smoke", "x"])).is_true()
	assert_bool(ReleaseSmoke.handles(["--server"])).is_false()
	var opts: Dictionary = ReleaseSmoke.parse(["--tts-smoke", "Hello.", "--out", "/t/a.wav"])
	assert_dict(opts).is_equal({"text": "Hello.", "out": "/t/a.wav", "voice": ""})
	assert_dict(ReleaseSmoke.parse(["--tts-smoke", "Hello."])).is_empty()
	assert_dict(ReleaseSmoke.parse(["--tts-smoke", "Hello.", "--out", "a.wav"])).is_empty()
