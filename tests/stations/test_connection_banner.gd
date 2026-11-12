extends GdUnitTestSuite
## The shell's connection banner (C1, C12 client half; R24-3, R11-2): "Reconnecting..." while
## it retries, then why it stopped, with Leave, and Take back after another window took over.


## A client the test drives by state; polling does nothing and a resume is counted.
class FakeClient:
	extends NetClient
	var resumes: int = 0

	func poll() -> void:
		pass

	func resume() -> Error:
		resumes += 1
		state = NetClient.State.CONNECTING
		return OK

	func bye(_reason: String = "") -> void:
		pass

	func take_events() -> Array[Dictionary]:
		return []


func after_test() -> void:
	I18n.apply("en")
	get_tree().root.content_scale_factor = 1.0


func _shell() -> ClientShell:
	var c: FakeClient = FakeClient.new()
	c.state = NetClient.State.WELCOMED
	c.welcome = {"session": 7, "ship": 0, "seat": "", "host": false, "lang": "en"}
	c.catalogue = StationFixture.catalogue()
	c.url = "ws://192.168.1.20:47801"
	var s: ClientShell = auto_free(ClientShell.new())
	s.setup(c, ClientSettings.new("user://test_connection_banner.cfg"))
	add_child(s)
	return s


func _banner(s: ClientShell) -> Label:
	return s.find_child("Banner", true, false) as Label


func _visible(s: ClientShell, node_name: String) -> bool:
	return (s.find_child(node_name, true, false) as Control).visible


# FT: FT-NET-025
# A drop shows "Reconnecting..." with no buttons and retries; after 20 s it says the host can't be
# reached and offers Leave and Try again, and no longer retries.
func test_a_lost_host_ends_in_leave_and_try_again() -> void:
	var s: ClientShell = _shell()
	var c: FakeClient = s.ctx.client as FakeClient
	assert_bool(s.find_child("LinkBanner", true, false).visible).is_false()
	c.state = NetClient.State.CLOSED
	s._link.update(c, 0)
	s._show_link()
	assert_str(_banner(s).text).is_equal(tr("shell.reconnecting"))
	assert_bool(_visible(s, "Leave")).is_false()
	s._link.update(c, LinkWatch.GIVE_UP_MS)
	s._show_link()
	assert_str(_banner(s).text).is_equal(JoinAdvice.gone())
	assert_bool(_visible(s, "Leave")).is_true()
	assert_bool(_visible(s, "TryAgain")).is_true()
	assert_bool(_visible(s, "TakeBack")).is_false()
	var before: int = c.resumes
	s._link.update(c, LinkWatch.GIVE_UP_MS * 2)
	assert_int(c.resumes).is_equal(before)
	# Try again resumes at once.
	(s.find_child("TryAgain", true, false) as Button).pressed.emit()
	assert_int(c.resumes).is_equal(before + 1)


# FT: FT-NET-025
# A rejected resume names the reason in plain words and offers Leave, which leaves.
func test_a_rejection_says_why_and_leave_leaves() -> void:
	var s: ClientShell = _shell()
	var c: FakeClient = s.ctx.client as FakeClient
	c.state = NetClient.State.REJECTED
	c.reject_reason = NetProtocol.REJECT_FULL
	s._link.update(c, 0)
	s._show_link()
	assert_str(_banner(s).text).is_equal(JoinAdvice.for_failure(NetProtocol.REJECT_FULL, c.url))
	assert_bool(_visible(s, "Leave")).is_true()
	var left: Array[bool] = [false]
	s.left.connect(func() -> void: left[0] = true)
	(s.find_child("Leave", true, false) as Button).pressed.emit()
	assert_bool(left[0]).is_true()


# FT: FT-NET-025, FT-NET-026
# After close 4001 the shell stops resuming and offers Take back, which resumes once.
func test_a_takeover_offers_take_back() -> void:
	var s: ClientShell = _shell()
	var c: FakeClient = s.ctx.client as FakeClient
	c.state = NetClient.State.CLOSED
	c.close_code = NetTransport.CLOSE_TAKEN_OVER
	assert_bool(s._link.update(c, 0)).is_false()
	s._show_link()
	assert_str(_banner(s).text).is_equal(tr("shell.taken_over"))
	assert_bool(_visible(s, "TakeBack")).is_true()
	assert_bool(_visible(s, "TryAgain")).is_false()
	assert_int(c.resumes).is_equal(0)
	(s.find_child("TakeBack", true, false) as Button).pressed.emit()
	assert_int(c.resumes).is_equal(1)
