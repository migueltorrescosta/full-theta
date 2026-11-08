class_name ThreadGuardHook
extends GdUnitTestSessionHook
## A gdUnit4 session hook (registered in project.godot) that fails the run naming every
## suite that left a thread running (#33). A NetTransport or PiperProcessSynth thread
## still running at exit deadlocks the engine's teardown: all tests pass, then the
## process spins for ever. The hook compares the live-thread counts before and after each
## suite and, at shutdown, writes thread-leaks.txt into the report directory (tools/gate.sh
## fails the shard when the file exists, and run_limited.sh names it in its warning).
## It also writes done.txt there, "passed" or "failed", once the last suite ended:
## tools/run_limited.sh reads that file to tell a hang at exit from a hang in a test,
## instead of scraping gdUnit4's console text.

var _session: GdUnitTestSession
var _before: int = 0
var _leaks: PackedStringArray = PackedStringArray()
var _failed: bool = false


func _init() -> void:
	super("ThreadGuard", "Fails the run when a test suite leaves a net or voice thread running.")


## Threads of the game's own classes started and not yet joined.
static func live_threads() -> int:
	return NetTransport.live_threads() + PiperProcessSynth.live_threads()


func startup(session: GdUnitTestSession) -> GdUnitResult:
	_session = session
	session.test_event.connect(_on_event)
	return GdUnitResult.success()


## Writes done.txt ("passed" or "failed") into `dir`.
static func write_done(dir: String, passed: bool) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("done.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("passed\n" if passed else "failed\n")


func shutdown(session: GdUnitTestSession) -> GdUnitResult:
	# The report directory itself (tools/gate.sh --report-directory), not its report_N folder.
	var dir: String = ProjectSettings.globalize_path(session.report_path).get_base_dir()
	write_done(dir, _leaks.is_empty() and not _failed)
	if _leaks.is_empty():
		return GdUnitResult.success()
	var text: String = "\n".join(_leaks)
	var file: FileAccess = FileAccess.open(dir.path_join("thread-leaks.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string(text + "\n")
	session.send_message("THREAD LEAK: " + text)
	return GdUnitResult.error("THREAD LEAK: " + text)


func _on_event(event: GdUnitEvent) -> void:
	if event.is_failed() or event.is_error():
		_failed = true
	match event.type():
		GdUnitEvent.TESTSUITE_BEFORE:
			_before = live_threads()
		GdUnitEvent.TESTSUITE_AFTER:
			var left: int = live_threads() - _before
			if left > 0:
				_leaks.append(
					(
						"%s left %d thread(s) running (net %d, voice %d)"
						% [
							event.resource_path(),
							left,
							NetTransport.live_threads(),
							PiperProcessSynth.live_threads()
						]
					)
				)
				_before = live_threads()
