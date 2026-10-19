extends GdUnitTestSuite
## The binding-table check (T055): one table (IntentTable.INTENTS) for every station and
## view, checked over every catalogue entry rather than per view.

## D176: in the cockpit and the turret a left click selects over a chip, mark or radar
## item and fires elsewhere, so Weapons' fire may share LMB with the common select.
const POINTER_EXEMPT: Array = [["fire", "kbm", "LMB"]]


## The ids a screen holding `stations` routes to `station` from `device` while
## `focused` has the focus.
static func _routed(station: String, device: String, focused: String, stations: Array) -> Array:
	var out: Array = []
	for r: Dictionary in IntentTable.INTENTS:
		if IntentTable.target(r["id"], device, focused, stations) == station:
			out.append(r["id"])
	return out


## The physical inputs of one binding: an axis pair splits ("S/W" is S and W), a sign or
## "long" doesn't change the input ("-RS_Y" is RS_Y, "long R3" is R3); chords stay whole.
static func _inputs(binding: String) -> Array:
	var out: Array = []
	for part: String in binding.trim_prefix("long ").split("/"):
		out.append(part.trim_prefix("-"))
	return out


# FT: FT-JNT-002, FT-JNT-001, FT-JNT-003, FT-M1-006
# Each station's bindings are the same in every view containing it: what a screen
# routes to a station depends only on the station, the device and the focused station,
# never on the view; and with its panel focused every binding of the station reaches it
# (every control is reachable).
func test_a_station_binds_the_same_in_every_view() -> void:
	var seen: Dictionary = {}
	for entry: String in StationViews.catalogue_ids(true):
		var stations: Array = StationViews.def(entry).stations
		for station: String in stations:
			for focused: String in stations:
				for device: String in IntentTable.DEVICES:
					var key: String = "%s|%s|%s" % [station, focused, device]
					var ids: Array = _routed(station, device, focused, stations)
					if seen.has(key):
						assert_array(ids).override_failure_message(key).is_equal(seen[key])
					seen[key] = ids
					if focused != station:
						continue
					for id: String in IntentTable.ids_of(station):
						if not IntentTable.defaults(id, device).is_empty():
							assert_array(ids).override_failure_message(key).contains([id])
	# The one cross-panel route: Tactical's cockpit fires with the KB/M fire buttons.
	assert_array(_routed("weapons", "kbm", "helm", ["helm", "weapons"])).is_equal(
		["fire", "fire_all"]
	)
	assert_array(_routed("weapons", "pad", "helm", ["helm", "weapons"])).is_empty()
	# A route `via` a focused station uses no input of that station.
	for r: Dictionary in IntentTable.INTENTS:
		for focused: String in r.get("via", {}):
			for device: String in r["via"][focused]:
				var own: Array = []
				for id: String in IntentTable.ids_of(focused):
					for b: String in IntentTable.defaults(id, device):
						own.append_array(_inputs(b))
				for b: String in IntentTable.defaults(r["id"], device):
					for i: Variant in _inputs(b):
						assert_bool(i in own).override_failure_message(r["id"]).is_false()


# FT: FT-STN-009, FT-JNT-002
# No station binding reuses a common or always-live input on the same device (the
# pointer case of D176 aside), and the always-live set collides with no station.
func test_no_station_binding_reuses_a_common_or_live_input() -> void:
	for device: String in IntentTable.DEVICES:
		var reserved: Dictionary = {}
		for r: Dictionary in IntentTable.INTENTS:
			if r["group"] == IntentTable.COMMON or IntentTable.is_live(r["id"], device):
				for b: String in IntentTable.defaults(r["id"], device):
					for i: Variant in _inputs(b):
						reserved[i] = r["id"]
		for r: Dictionary in IntentTable.INTENTS:
			if r["group"] == IntentTable.COMMON or IntentTable.is_live(r["id"], device):
				continue
			for b: String in IntentTable.defaults(r["id"], device):
				if [r["id"], device, b] in POINTER_EXEMPT:
					continue
				for i: Variant in _inputs(b):
					(
						assert_bool(reserved.has(i))
						. override_failure_message(
							"%s %s %s reuses %s's" % [r["id"], device, b, reserved.get(i)]
						)
						. is_false()
					)


# FT: FT-HLM-017, FT-STN-005
# Every Helm action has a controller binding: its own, or an item of the Helm radial
# (hold View + right stick); only the KB/M pointer hold (Ctrl frees the mouse) has
# nothing to free on a controller.
func test_every_helm_action_has_a_controller_binding() -> void:
	for id: String in IntentTable.ids_of("helm"):
		if id == "helm_pointer":
			continue
		var pad: bool = not IntentTable.defaults(id, IntentTable.PAD).is_empty()
		(
			assert_bool(pad or id in HelmPanel.RADIAL)
			. override_failure_message(id + " has no controller binding")
			. is_true()
		)
	assert_bool(IntentTable.defaults("helm_radial", IntentTable.PAD).is_empty()).is_false()
