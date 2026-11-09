extends GdUnitTestSuite
## The client names commands and NetClient intents as strings (F8, R13-12): ShipIntents calls
## NetClient methods by name and falls back silently when one is missing, and the stations
## build crew commands as {"kind": ...} literals. These checks make a rename on either side
## fail here rather than drop an intent in play.

const INTENTS: String = "res://stations/ship_intents.gd"
const CLIENT_DIRS: Array[String] = ["res://stations", "res://presentation", "res://input"]


func _sources(dir: String, out: Dictionary) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var path: String = dir.path_join(f)
			out[path] = FileAccess.get_file_as_string(path)
	for d: String in DirAccess.get_directories_at(dir):
		_sources(dir.path_join(d), out)


# FT: FT-NET-006
func test_every_intent_names_a_net_client_method() -> void:
	var methods: Dictionary = {}
	for m: Dictionary in (NetClient as Script).get_script_method_list():
		methods[m["name"]] = true
	var re: RegEx = RegEx.create_from_string('_call\\(&"(\\w+)"')
	var found: Array[RegExMatch] = re.search_all(FileAccess.get_file_as_string(INTENTS))
	assert_int(found.size()).is_greater(30)
	for m: RegExMatch in found:
		(
			assert_bool(methods.has(m.get_string(1)))
			. override_failure_message(
				"ShipIntents calls NetClient.%s, which does not exist" % m.get_string(1)
			)
			. is_true()
		)


# FT: FT-NET-006
func test_every_command_kind_a_station_sends_is_a_station_command() -> void:
	var known: Dictionary = {}
	for station: String in StationViews.STATION_COMMANDS:
		for kind: StringName in StationViews.STATION_COMMANDS[station]:
			known[String(kind)] = true
	var sources: Dictionary = {}
	for dir: String in CLIENT_DIRS:
		_sources(dir, sources)
	var re: RegEx = RegEx.create_from_string('command\\(\\s*\\{\\s*"kind":\\s*"(\\w+)"')
	var n: int = 0
	for path: String in sources:
		for m: RegExMatch in re.search_all(sources[path]):
			n += 1
			(
				assert_bool(known.has(m.get_string(1)))
				. override_failure_message(
					"%s sends command kind %s, which no station owns" % [path, m.get_string(1)]
				)
				. is_true()
			)
	assert_int(n).is_greater(40)
