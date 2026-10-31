class_name Frames
extends RefCounted
## Waiting for frames in a test without hanging the shard (#33). `wait` awaits `count`
## frames and fails the running test, with a message naming `what`, when they take more
## than `limit_ms` of wall time (a frame that never ends cannot be interrupted, but the
## gate's shard limit kills it and prints this test's name; a slow frame fails here).

const LIMIT_MS: int = 20000


## Awaits `count` frames of `tree`; false (after failing the test) if they took too long.
static func wait(
	tree: SceneTree, count: int = 1, what: String = "frames", limit_ms: int = LIMIT_MS
) -> bool:
	var end: int = Time.get_ticks_msec() + limit_ms
	for i: int in count:
		await tree.process_frame
		if Time.get_ticks_msec() > end:
			(
				GdUnitTestSuite
				. assert_bool(false)
				. override_failure_message(
					"%s: frame %d of %d came after more than %d ms" % [what, i + 1, count, limit_ms]
				)
				. is_true()
			)
			return false
	return true
