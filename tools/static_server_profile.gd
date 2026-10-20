extends SceneTree
## Manual check of FT-NET-039's HTTP budget (D108): times the search for the end of a
## request head over a whole 8 KiB headerless request (letters, then line feeds, the
## slow case of a byte loop), the most one poll searches. Wall-clock, so not a gate
## test (tests/net/test_host_static_server.gd counts the bytes searched instead); run
## it on an idle host and record the load average with the result:
##
## taskset -c 0,1 godot --headless --path . -s res://tools/static_server_profile.gd
##
## Exits 1 when a median search is not under StaticServer.DEFAULT_BUDGET_US.

const SIZE: int = 8190
const RUNS: int = 201


func _initialize() -> void:
	var over: bool = false
	for fill: int in [65, 10]:
		var buf: PackedByteArray = PackedByteArray()
		buf.resize(SIZE)
		buf.fill(fill)
		var times: Array[int] = []
		for i: int in RUNS:
			var t0: int = Time.get_ticks_usec()
			StaticServer._header_end(buf)
			times.append(Time.get_ticks_usec() - t0)
		times.sort()
		var median: int = times[RUNS / 2]
		print(
			(
				"fill %d: median %d us, max %d us, budget %d us"
				% [fill, median, times[-1], StaticServer.DEFAULT_BUDGET_US]
			)
		)
		over = over or median >= StaticServer.DEFAULT_BUDGET_US
	quit(1 if over else 0)
