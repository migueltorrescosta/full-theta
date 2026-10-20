# FT: FT-M1-016
extends GdUnitTestSuite
## The client test flags docs/launch.md uses (ClientAutopilot).


func test_reads_the_flags() -> void:
	var p: ClientAutopilot = auto_free(ClientAutopilot.new())
	var args: PackedStringArray = ["--auto-join", "10.0.0.2:47801", "--screenshot", "/tmp/a.png"]
	assert_bool(ClientAutopilot.wanted(args)).is_true()
	assert_bool(p.parse_args(args)).is_true()
	assert_str(p.join_address).is_equal("10.0.0.2:47801")
	assert_str(p.screenshot).is_equal("/tmp/a.png")
	assert_float(p.quit_after).is_equal(10.0)


func test_refuses_a_bad_command_line() -> void:
	assert_bool(ClientAutopilot.wanted(["--server", "--bind", "127.0.0.1"])).is_false()
	assert_bool(auto_free(ClientAutopilot.new()).parse_args(["--auto-host"])).is_false()
	assert_bool(auto_free(ClientAutopilot.new()).parse_args(["--quit-after", "soon"])).is_false()
