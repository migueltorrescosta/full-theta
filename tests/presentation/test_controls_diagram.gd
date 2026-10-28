extends GdUnitTestSuite
## ControlsDiagram, ControlsModel and ControlsPane (FT-STN-011, D185): every binding of
## the game on one keyboard-and-mouse and one controller diagram, labels from the live
## bindings, the screen's stations highlighted.
# FT: FT-STN-011, FT-STN-012

## The six stations of the dev seat, the largest diagram.
const SIX: Array = ["helm", "weapons", "engineering", "science", "relay", "comms"]


## Runs the incremental _uncross and the old full recount on every column it orders, and
## records any column they order differently.
class RecountDiagram:
	extends ControlsDiagram
	var columns: int = 0
	var mismatches: Array[String] = []

	func _uncross(list: Array, ys: Array[float], elbow_x: float) -> void:
		var ref: Array = list.duplicate()
		_full_recount_uncross(ref, ys, elbow_x)
		super._uncross(list, ys, elbow_x)
		columns += 1
		if ref != list:
			mismatches.append(str(list.map(func(l: Dictionary) -> String: return l["id"])))

	## The order before load fix 8: every trade recounted the whole column.
	func _full_recount_uncross(list: Array, ys: Array[float], elbow_x: float) -> void:
		var swapped: bool = true
		var rounds: int = 0
		while swapped and rounds < 300:
			swapped = false
			rounds += 1
			for i: int in list.size():
				for j: int in range(i + 1, list.size()):
					if _labels_cross(list[i], ys[i], list[j], ys[j], elbow_x):
						var t: Variant = list[i]
						list[i] = list[j]
						list[j] = t
						swapped = true
		var best: float = _full_cost(list, ys, elbow_x)
		var improved: bool = true
		var guard: int = 0
		while improved and guard < 60:
			improved = false
			guard += 1
			for i: int in list.size():
				for j: int in range(i + 1, list.size()):
					var tmp: Variant = list[i]
					list[i] = list[j]
					list[j] = tmp
					var c: float = _full_cost(list, ys, elbow_x)
					if c < best - 0.001:
						best = c
						improved = true
					else:
						list[j] = list[i]
						list[i] = tmp

	func _full_cost(list: Array, ys: Array[float], elbow_x: float) -> float:
		var segs: Array = []
		var length: float = 0.0
		for i: int in list.size():
			var e: Vector2 = Vector2(elbow_x, ys[i] + (LINE_H - 2.0) * 0.5)
			for a: Vector2 in list[i]["lead"]:
				segs.append([i, e, a])
				length += e.distance_to(a)
			var chain: Array = list[i]["anchors"]
			for k: int in range(1, chain.size()):
				segs.append([i, chain[k - 1], chain[k]])
		var crossings: int = 0
		for i: int in segs.size():
			for j: int in range(i + 1, segs.size()):
				if (
					segs[i][0] != segs[j][0]
					and segments_cross(segs[i][1], segs[i][2], segs[j][1], segs[j][2])
				):
					crossings += 1
		return crossings * 1000000.0 + length


func before() -> void:
	I18n.apply("en")


func after() -> void:
	I18n.apply("en")
	LayoutMode.forced = -1


func _model(bindings: Bindings, stations: Array, device: String) -> ControlsModel:
	var m: ControlsModel = ControlsModel.new()
	m.build(bindings, stations, device)
	return m


func _diagram(bindings: Bindings, stations: Array, device: String) -> ControlsDiagram:
	var d: ControlsDiagram = auto_free(ControlsDiagram.new())
	d.build(bindings, stations, device)
	return d


func test_every_binding_is_listed_exactly_once_or_marked_unbound() -> void:
	var bindings: Bindings = Bindings.new()
	for device: String in IntentTable.DEVICES:
		var m: ControlsModel = _model(bindings, ["helm"], device)
		var want: int = 0
		for r: Dictionary in IntentTable.INTENTS:
			var id: String = r["id"]
			var list: PackedStringArray = IntentTable.defaults(id, device)
			if list.is_empty():
				assert_array(m.unbound).contains([id])
				(
					assert_array(
						m.entries.filter(func(e: Dictionary) -> bool: return e["id"] == id)
					)
					. is_empty()
				)
				continue
			assert_array(m.unbound).not_contains([id])
			for b: String in list:
				want += 1
				var hits: Array = m.entries.filter(
					func(e: Dictionary) -> bool: return e["id"] == id and e["binding"] == b
				)
				(
					assert_int(hits.size())
					. override_failure_message("%s %s %s" % [device, id, b])
					. is_equal(1)
				)
		assert_int(m.entries.size()).is_equal(want)


func test_every_default_binding_has_a_place_on_the_drawing() -> void:
	for device: String in IntentTable.DEVICES:
		var m: ControlsModel = _model(Bindings.new(), IntentTable.GROUPS, device)
		var lost: Array = m.unmapped().map(
			func(e: Dictionary) -> String: return e["id"] + " " + e["binding"]
		)
		assert_array(lost).override_failure_message(device).is_empty()


func test_chords_pairs_and_sticks_land_on_their_parts() -> void:
	var known: Dictionary = ControlsFigure.ids(IntentTable.KBM)
	assert_array(ControlsModel.parts_of("Alt+A", known)).is_equal(["A"])
	assert_array(ControlsModel.parts_of("S/W", known)).is_equal(["S", "W"])
	assert_array(ControlsModel.parts_of("Shift+MMB", known)).is_equal(["MMB"])
	assert_array(ControlsModel.parts_of("MouseX", known)).is_equal(["Mouse"])
	assert_array(ControlsModel.parts_of("F13", known)).is_empty()
	known = ControlsFigure.ids(IntentTable.PAD)
	assert_array(ControlsModel.parts_of("LB+LS_X", known)).is_equal(["LS"])
	assert_array(ControlsModel.parts_of("long R3", known)).is_equal(["RS"])
	assert_array(ControlsModel.parts_of("-RS_Y", known)).is_equal(["RS"])
	assert_array(ControlsModel.parts_of("View+Y", known)).is_equal(["Y"])
	assert_array(ControlsModel.parts_of("LT/RT", known)).is_equal(["LT", "RT"])


func test_a_rebind_changes_the_label_and_the_key() -> void:
	var bindings: Bindings = Bindings.new()
	var d: ControlsDiagram = _diagram(bindings, ["helm"], IntentTable.KBM)
	assert_str(_label(d, "face")["keys"]).is_equal(BindingText.describe("F"))
	assert_array(_label(d, "face")["parts"]).is_equal(["F"])
	bindings.rebind("face", IntentTable.KBM, PackedStringArray(["Shift+K"]))
	assert_str(_label(d, "face")["keys"]).is_equal("Shift+K")
	assert_array(_label(d, "face")["parts"]).is_equal(["K"])
	assert_str(d.part_emphasis("F")).is_equal("")
	assert_str(d.part_emphasis("K")).is_equal("station")
	bindings.set_toggle("face", true)
	assert_str(_label(d, "face")["keys"]).ends_with("(toggle)")
	bindings.rebind("face", IntentTable.KBM, PackedStringArray())
	assert_dict(_label(d, "face")).is_empty()
	assert_array(d.model.unbound).contains(["face"])
	# A key the drawing has no part for is listed apart, not lost.
	bindings.rebind("face", IntentTable.KBM, PackedStringArray(["F13"]))
	(
		assert_array(d.model.unmapped().map(func(e: Dictionary) -> String: return e["id"]))
		. contains(["face"])
	)


func test_the_current_stations_keys_are_highlighted_and_the_rest_dimmed() -> void:
	var bindings: Bindings = Bindings.new()
	var weapons: ControlsDiagram = _diagram(bindings, ["weapons"], IntentTable.KBM)
	assert_str(weapons.part_emphasis("1")).is_equal("station")
	assert_str(weapons.part_emphasis("Space")).is_equal("other")
	assert_str(weapons.part_emphasis("T")).is_equal("common")
	assert_str(weapons.part_emphasis("F13")).is_equal("")
	var helm: ControlsDiagram = _diagram(bindings, ["helm"], IntentTable.KBM)
	assert_str(helm.part_emphasis("Space")).is_equal("station")
	assert_str(helm.part_emphasis("1")).is_equal("other")
	# Only the station's and the common intents have callouts.
	var groups: Array = helm.labels().map(func(l: Dictionary) -> String: return l["group"])
	assert_array(groups).not_contains(["weapons", "engineering", "science"])
	assert_array(groups).contains(["helm", IntentTable.COMMON, IntentTable.LIVE])
	var pad: ControlsDiagram = _diagram(bindings, ["weapons"], IntentTable.PAD)
	assert_str(pad.part_emphasis("RT")).is_equal("station")


func test_labels_are_translated_and_follow_the_language() -> void:
	var d: ControlsDiagram = _diagram(Bindings.new(), ["helm"], IntentTable.KBM)
	add_child(d)
	assert_str(_label(d, "face")["label"]).is_equal("Face selection")
	I18n.apply("it")
	var it: String = _label(d, "face")["label"]
	assert_str(it).is_not_equal("Face selection")
	assert_str(it).is_equal(tr(IntentTable.label_key("face")))


# The dev seat's six stations and every station (the All stations filter, P28-Help) too.
func test_callouts_neither_overlap_nor_leave_the_drawing() -> void:
	var bounds: Rect2 = Rect2(0.0, 0.0, ControlsDiagram.DESIGN_W, 0.0)
	var every: Array = IntentTable.GROUPS.filter(
		func(g: String) -> bool: return g not in [IntentTable.COMMON, IntentTable.LIVE]
	)
	for stations: Array in [
		["helm", "weapons"],
		["science"],
		["comms"],
		["captain"],
		["engineering", "relay"],
		SIX,
		every
	]:
		for device: String in IntentTable.DEVICES:
			var d: ControlsDiagram = _diagram(Bindings.new(), stations, device)
			bounds.size.y = d.design_height()
			var rects: Array[Rect2] = []
			for l: Dictionary in d.labels():
				var r: Rect2 = l["rect"]
				var why: String = "%s %s %s" % [stations, device, l["id"]]
				assert_bool(bounds.encloses(r)).override_failure_message(why).is_true()
				for other: Rect2 in rects:
					assert_bool(other.intersects(r)).override_failure_message(why).is_false()
				rects.append(r)
			# Alternative keys ("S / W") get a callout each.
			assert_int(rects.size()).is_greater_equal(d.model.callouts().size())


func test_no_two_leader_lines_cross() -> void:
	for stations: Array in [
		["helm", "weapons"],
		["helm"],
		["weapons"],
		["science"],
		["comms"],
		["captain"],
		["engineering"],
		["relay"],
		["engineering", "relay"]
	]:
		for device: String in IntentTable.DEVICES:
			var d: ControlsDiagram = _diagram(Bindings.new(), stations, device)
			var segs: Array[Dictionary] = []
			for ld: Dictionary in d.leaders():
				var pts: PackedVector2Array = ld["points"]
				for i: int in pts.size() - 1:
					segs.append({"id": ld["id"], "a": pts[i], "b": pts[i + 1]})
			for i: int in segs.size():
				for j: int in range(i + 1, segs.size()):
					if segs[i]["id"] == segs[j]["id"]:
						continue
					var why: String = (
						"%s %s: %s x %s" % [stations, device, segs[i]["id"], segs[j]["id"]]
					)
					(
						assert_bool(
							ControlsDiagram.segments_cross(
								segs[i]["a"], segs[i]["b"], segs[j]["a"], segs[j]["b"]
							)
						)
						. override_failure_message(why)
						. is_false()
					)


func test_a_phone_opens_on_the_list_and_the_rest_on_the_device_in_use() -> void:
	assert_str(ControlsPane.default_view(true, IntentTable.KBM)).is_equal(ControlsPane.VIEW_LIST)
	assert_str(ControlsPane.default_view(false, IntentTable.KBM)).is_equal(ControlsPane.VIEW_KBM)
	assert_str(ControlsPane.default_view(false, IntentTable.PAD)).is_equal(ControlsPane.VIEW_PAD)


func test_the_pane_keeps_the_list_and_the_role_summary() -> void:
	var pane: ControlsPane = auto_free(ControlsPane.new())
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM, "helm")
	assert_str(pane.view).is_equal(ControlsPane.VIEW_KBM)
	assert_bool(pane.list.visible).is_false()
	assert_array(pane.list.rows()).is_not_empty()
	pane.show_view(ControlsPane.VIEW_LIST)
	assert_bool(pane.list.visible).is_true()
	assert_bool(pane.kbm.get_parent().visible).is_false()
	var texts: Array = pane.find_children("*", "Label", true, false).map(
		func(l: Node) -> String: return (l as Label).text
	)
	assert_array(texts).contains([tr("role.helm")])


# Load fix 8: the incremental trade gives the same order as the full recount it replaces.
func test_the_incremental_uncross_orders_as_the_full_recount() -> void:
	for stations: Array in [
		["helm", "weapons"],
		["helm"],
		["weapons"],
		["science"],
		["comms"],
		["captain"],
		["engineering"],
		["relay"],
		["engineering", "relay"],
		SIX
	]:
		for device: String in IntentTable.DEVICES:
			ControlsDiagram.clear_cache()
			var d: RecountDiagram = auto_free(RecountDiagram.new())
			d.build(Bindings.new(), stations, device)
			var why: String = "%s %s" % [stations, device]
			assert_int(d.columns).override_failure_message(why).is_greater(0)
			assert_array(d.mismatches).override_failure_message(why).is_empty()


# Load fix 1: a second diagram with the same stations, device, bindings and language reuses
# the layout; a rebind or another language lays it out again.
func test_a_layout_is_reused_until_something_it_shows_changes() -> void:
	ControlsDiagram.clear_cache()
	var bindings: Bindings = Bindings.new()
	var a: ControlsDiagram = _diagram(bindings, SIX, IntentTable.KBM)
	var b: ControlsDiagram = _diagram(bindings, SIX, IntentTable.KBM)
	assert_object(b.labels()).is_same(a.labels())
	assert_float(b.design_height()).is_equal(a.design_height())
	var before: Array[Dictionary] = b.labels()
	bindings.rebind("face", IntentTable.KBM, PackedStringArray(["Shift+K"]))
	assert_object(b.labels()).is_not_same(before)
	assert_str(_label(b, "face")["keys"]).is_equal("Shift+K")
	var c: ControlsDiagram = _diagram(Bindings.new(), SIX, IntentTable.KBM)
	assert_str(_label(c, "face")["keys"]).is_equal(BindingText.describe("F"))


# FT: FT-STN-011, FT-STN-012
# Load fix 1: the pane builds a diagram only when it shows; the list is always there.
func test_the_pane_builds_a_diagram_only_when_it_shows() -> void:
	var pane: ControlsPane = auto_free(ControlsPane.new())
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM, "helm")
	assert_array(pane.kbm.shown_args()).is_not_empty()
	assert_array(pane.pad.shown_args()).is_empty()
	pane.show_view(ControlsPane.VIEW_PAD)
	assert_array(pane.pad.shown_args()).is_not_empty()


# FT: FT-STN-011, FT-STN-012
# A phone shows the list and never builds a diagram.
func test_a_phone_never_builds_a_diagram() -> void:
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), SIX, IntentTable.PAD, "all")
	pane.show_view(ControlsPane.VIEW_PAD)
	assert_str(pane.view).is_equal(ControlsPane.VIEW_LIST)
	assert_bool(pane.list.visible).is_true()
	assert_array(pane.kbm.shown_args()).is_empty()
	assert_array(pane.pad.shown_args()).is_empty()
	assert_bool((pane.find_child(ControlsPane.VIEW_KBM, true, false) as Control).visible).is_false()


# FT: FT-STN-011, FT-STN-012
# P28-Help: my stations by default, every station with the filter.
func test_the_filter_shows_every_station() -> void:
	var pane: ControlsPane = auto_free(ControlsPane.new())
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM, "helm")
	var sections: Callable = func() -> Array:
		return pane.list.rows().map(func(r: Dictionary) -> String: return r["section"])
	assert_array(sections.call()).not_contains(["station.weapons"])
	(
		assert_array(
			pane.kbm.model.callouts().map(func(e: Dictionary) -> String: return e["group"])
		)
		. not_contains(["weapons"])
	)
	pane.set_all_stations(true)
	assert_array(sections.call()).contains(["station.helm", "station.weapons", "station.comms"])
	(
		assert_array(
			pane.kbm.model.callouts().map(func(e: Dictionary) -> String: return e["group"])
		)
		. contains(["weapons"])
	)
	pane.set_all_stations(false)
	assert_array(sections.call()).not_contains(["station.weapons"])


func test_the_station_colours_exist_for_every_group() -> void:
	for g: String in IntentTable.GROUPS:
		if g in [IntentTable.COMMON, IntentTable.LIVE]:
			continue
		assert_bool(Palette.ROLES.has("st_" + g)).override_failure_message(g).is_true()


func _label(d: ControlsDiagram, id: String) -> Dictionary:
	for l: Dictionary in d.labels():
		if l["id"] == id:
			return l
	return {}
