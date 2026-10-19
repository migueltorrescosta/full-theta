extends GdUnitTestSuite
## VoiceSetup (app/): the host's voice composition picks the Piper adapter per build.

const STUB: String = "res://tests/net/voice/bundled_piper_stub.gd"


func after_test() -> void:
	VoiceSetup.reset()


# FT: FT-AUD-019
# An exported build drives the bundled binary with BundledPiper's paths; a voice it
# doesn't bundle, or a build without BundledPiper, gives no synth (subtitles only).
func test_exported_builds_use_the_bundled_binary() -> void:
	VoiceSetup.exported = true
	VoiceSetup.bundled_lookup = func() -> Object: return load(STUB)
	var synth: VoiceSynth = VoiceSetup.make("en_GB-cori-medium")
	assert_object(synth).is_instanceof(PiperBinarySynth)
	var bin: PiperBinarySynth = synth
	assert_str(bin.binary).is_equal("/game/piper/piper")
	assert_str(bin.espeak_data).is_equal("/game/piper/espeak-ng-data")
	assert_str(bin.model).is_equal("/game/voices/en_GB-cori-medium/en_GB-cori-medium.onnx")
	assert_object(VoiceSetup.make("pt_PT-tugão-medium")).is_null()
	VoiceSetup.bundled_lookup = func() -> Object: return null
	assert_object(VoiceSetup.make("en_GB-cori-medium")).is_null()


# FT: FT-AUD-019
# In development a missing model gives no synth; the service gets the clip folder.
func test_development_and_service() -> void:
	VoiceSetup.exported = false
	assert_object(VoiceSetup.make("no-such-voice")).is_null()
	var svc: VoiceService = VoiceSetup.make_service(NetTransport.new(), func() -> int: return 3)
	assert_str(svc.clip_dir).is_equal("res://audio/prerendered_host")
	assert_int(svc.tick_source.call()).is_equal(3)
	# The factory is static, so it outlives any VoiceSetup instance.
	assert_bool(svc.synth_factory.is_valid()).is_true()
	svc.free()
