extends RefCounted
## Stands in for the packaging strand's BundledPiper (same static API) in VoiceSetup tests.


static func paths() -> Dictionary:
	return {
		"program": "/game/piper/piper",
		"data": "/game/piper/espeak-ng-data",
		"voices": "/game/voices"
	}


static func voices() -> PackedStringArray:
	return PackedStringArray(["en_GB-cori-medium"])
