extends GdUnitTestSuite
## The Captain's priority target on the client (gp-15): the `priority` event reaches the
## crew model, flags the contact in the shared picture Helm and Weapons draw, toasts once on
## Helm and Weapons only, and the Captain's Priority and Clear priority show only when they
## act. Viewer pings (gp-15) and the pending site's "?" flag (gp-16) on the client too.

const SETTINGS: String = "user://test_priority_target.cfg"
const H2: int = StationFixture.H2


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	LayoutMode.forced = LayoutMode.Kind.DESKTOP


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _event(ctx: StationContext, contact: int, by: String = "Bo") -> void:
	var payload: Dictionary = {"ship": StationFixture.SHIP, "contact": contact}
	payload.merge({"callsign": "H2" if contact == H2 else "", "by": by})
	ctx.crew.handle_event({"type": NetProtocol.EVENT_PRIORITY, "payload": payload}, 0)


func _screen(seat: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(seat, SETTINGS)
	if seat == StationCatalogue.CAPTAIN:
		CommsFixture.install(ctx)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


# FT: FT-CPT-006
# The event sets the model and flags only that contact in the picture; Helm and Weapons get
# "Captain: priority H2" once, a rejoin's replay (no `by`) and other stations get no toast,
# and a run reset clears it.
func test_the_event_flags_the_picture_and_toasts_on_helm_and_weapons() -> void:
	for seat: String in ["helm", "weapons", "science"]:
		var ctx: StationContext = StationFixture.context(seat, SETTINGS)
		var toasts: Array = []
		ctx.crew.toast.connect(
			func(key: String, args: Dictionary) -> void: toasts.append([key, args])
		)
		_event(ctx, H2)
		assert_int(ctx.crew.priority).is_equal(H2)
		for it: Dictionary in ctx.picture().items:
			assert_bool(it.get("priority", false)).override_failure_message(str(it["id"])).is_equal(
				it["kind"] == "contact" and it["id"] == H2
			)
		if seat == "science":
			assert_array(toasts).is_empty()
		else:
			assert_array(toasts).is_equal([["toast.priority", {"callsign": "H2"}]])
			assert_str(tr("toast.priority").format(toasts[0][1])).is_equal("Captain: priority H2")
		_event(ctx, H2)
		_event(ctx, -1)
		assert_int(ctx.crew.priority).is_equal(-1)
		assert_bool(ctx.picture().find({"kind": "contact", "id": H2}).has("priority")).is_false()
		_event(ctx, H2, "")
		assert_int(toasts.size()).is_equal(0 if seat == "science" else 1)
		ctx.crew.reset_run()
		assert_int(ctx.crew.priority).is_equal(-1)


# FT: FT-CPT-006, FT-CPT-003
# Priority shows only while a contact other than the target is selected, Clear priority only
# while one is set, beside the view buttons and on the phone's selection sheet; each sends
# PriorityTarget.
func test_the_captain_actions_show_only_when_they_act() -> void:
	var s: StationScreen = await _screen(StationCatalogue.CAPTAIN)
	var cap: CaptainPanel = s.panels[0] as CaptainPanel
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	s.ctx.crew.select("", -1)
	cap._process(0.016)
	assert_bool(cap.priority_button.visible).is_false()
	assert_bool(cap.clear_priority_button.visible).is_false()
	assert_array(cap.selection_extras).is_empty()
	s.ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	cap._process(0.016)
	assert_bool(cap.priority_button.visible).is_false()
	s.ctx.crew.select("contact", H2)
	cap._process(0.016)
	assert_bool(cap.priority_button.visible).is_true()
	assert_str(cap.priority_button.text).is_equal("Priority")
	cap.priority_button.pressed.emit()
	assert_array(rec.sent.back()).is_equal(["set_priority", [H2]])
	_event(s.ctx, H2)
	cap._process(0.016)
	assert_bool(cap.priority_button.visible).is_false()
	assert_bool(cap.clear_priority_button.visible).is_true()
	assert_str(str(cap.selection_extras[0][0])).is_equal("Clear priority")
	(cap.selection_extras[0][1] as Callable).call()
	assert_array(rec.sent.back()).is_equal(["set_priority", [-1]])


# FT: FT-MSC-004
# A plain viewer's main screen picks only contacts, and its select on one pings it; a ping
# with `viewer` names its pinger "Viewer Ana" on every screen.
func test_a_viewer_click_pings_a_contact() -> void:
	var s: StationScreen = await _screen(StationCatalogue.VIEWER)
	var v: ViewerPanel = s.panels[0] as ViewerPanel
	v.update_view(0.016)
	var at: Vector2 = Vector2(-1, -1)
	for e: Dictionary in v.radar._layout():
		if e["item"]["kind"] == "contact" and e["item"]["id"] == H2:
			at = v.radar.position + (e["pos"] as Vector2)
	assert_bool(at.x >= 0.0).is_true()
	assert_dict(v.item_at(at)).is_equal({"kind": "contact", "id": H2})
	assert_dict(v.item_at(Vector2(2, 2))).is_empty()
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	# The screen's select under the pointer finds it and pings it (the mouse doesn't move in
	# headless tests, so the point goes in directly).
	s.common.select_item(s.common.item_at_point(v.get_global_transform() * at))
	assert_bool(s.ctx.crew.is_selected("contact", H2)).is_true()
	assert_array(rec.of("ping")).is_equal([["ping", ["contact", H2, Vector3.ZERO]]])
	var payload: Dictionary = {"ship": StationFixture.SHIP, "kind": "contact", "id": H2}
	payload.merge({"by": "Ana", "viewer": true, "copy": ""})
	s.ctx.crew.handle_event({"type": "ping", "payload": payload}, StationFixture.NOW_MS)
	assert_str(s.ctx.crew.pings.back()["by"]).is_equal("Viewer Ana")


# FT: FT-RLY-012
# The SITES row's pending flag reaches the picture's site item Relay's map draws as "?";
# a row without it is not pending.
func test_the_pending_flag_reaches_the_picture() -> void:
	var ctx: StationContext = StationFixture.context("relay", SETTINGS)
	ctx.snap.sites = [
		{
			"id": 3,
			"name_key": "site.vesper",
			"kind": &"nav",
			"dockable": false,
			"pending": true,
			"radius": 3000.0,
			"pos": StationFixture.OWN_POS + Vector3(4000, 0, 0)
		},
		{
			"id": 4,
			"name_key": "site.other",
			"kind": &"nav",
			"dockable": false,
			"radius": 3000.0,
			"pos": StationFixture.OWN_POS
		},
	]
	var sites: Array[Dictionary] = ctx.picture().sites
	assert_bool(sites[0]["pending"]).is_true()
	assert_bool(sites[1]["pending"]).is_false()
