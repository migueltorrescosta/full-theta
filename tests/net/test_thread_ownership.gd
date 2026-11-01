extends GdUnitTestSuite
## A net thread left running at the end of the process deadlocks the engine's exit
## (all tests pass, then the process spins for ever, #33). The owner of a started
## NetTransport stops it when it is freed, in or out of the tree, so the live-thread
## count returns to where it was; tests/thread_guard_hook.gd checks it after every suite.

var _base: int = 0


func before_test() -> void:
	_base = ThreadGuardHook.live_threads()


func _server() -> NetServer:
	var s: NetServer = NetServer.new()
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	m1.science = load("res://content/science/science.tres") as ScienceDef
	assert_int(s.start(m1, 0, "127.0.0.1", false, "")).is_equal(OK)
	return s


# FT: FT-NET-040
func test_a_started_transport_counts_until_stopped() -> void:
	var t: NetTransport = NetTransport.new()
	assert_int(t.start(0, "127.0.0.1")).is_equal(OK)
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base + 1)
	t.stop()
	t.stop()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base)


# FT: FT-NET-040
func test_a_server_freed_outside_the_tree_stops_its_thread() -> void:
	var s: NetServer = _server()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base + 1)
	s.free()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base)


# FT: FT-NET-040
func test_a_server_freed_in_the_tree_stops_its_thread() -> void:
	var s: NetServer = _server()
	add_child(s)
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base + 1)
	s.free()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base)


# FT: FT-NET-040
func test_the_harness_stops_servers_before_free_all_returns_to_the_caller() -> void:
	var h: NetHarness = NetHarness.new(self)
	h.server()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base + 1)
	# Not awaited, like the suites' after_test: the thread must already be stopped.
	h.free_all()
	assert_int(ThreadGuardHook.live_threads()).is_equal(_base)
	await get_tree().process_frame
