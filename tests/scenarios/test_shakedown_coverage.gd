extends GdUnitTestSuite
## The Shakedown teaches every control (FT-MIS-039, D235): each IntentTable row of every
## station group, and the common rows, has exactly one step on each track that has it, a
## worked example and a line in all three languages; the data agrees with the code.

const LANGS: Array[String] = ["en", "pt_PT", "it"]
const STATIONS: Array[String] = [
	"helm", "weapons", "engineering", "science", "relay", "comms", "captain"
]
## The Next control itself is not a step.
const NOT_TAUGHT: Array[String] = ["training_next"]

var steps: TrainingStepsDef
var lines: DialogueLines
var strings: Dictionary


func before_test() -> void:
	steps = load("res://content/training/steps.tres") as TrainingStepsDef
	lines = DialogueLines.load_dir()
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/i18n/strings.json")
	)
	strings = (parsed as Dictionary)["strings"]


func _steps_of(station: String, intent: String) -> Array[TrainingStepDef]:
	return steps.steps.filter(
		func(s: TrainingStepDef) -> bool:
			return String(s.station) == station and String(s.intent) == intent
	)


## The intents a station's track must teach: its group, the common rows, the always-live set.
func _wanted(station: String) -> Array[String]:
	var out: Array[String] = IntentTable.ids_of(station)
	out.append_array(IntentTable.ids_of(IntentTable.COMMON))
	for id: String in IntentTable.ids_of(IntentTable.LIVE):
		if not NOT_TAUGHT.has(id):
			out.append(id)
	return out


# FT: FT-MIS-039
func test_the_step_data_is_valid() -> void:
	assert_array(steps.validate()).is_empty()


# FT: FT-MIS-039
func test_every_row_has_exactly_one_step_per_track() -> void:
	for station: String in STATIONS:
		for id: String in _wanted(station):
			(
				assert_array(_steps_of(station, id))
				. override_failure_message("%s/%s" % [station, id])
				. has_size(1)
			)
		assert_int(steps.track(StringName(station)).size()).is_equal(_wanted(station).size())
	# Every step teaches a real row (or is a pair step).
	for s: TrainingStepDef in steps.steps:
		if not s.is_pair():
			assert_bool(IntentTable.has(String(s.intent))).is_true()


# FT: FT-MIS-039
func test_every_step_has_a_line_and_a_worked_example_in_all_languages() -> void:
	for s: TrainingStepDef in steps.steps:
		var line: Dictionary = lines.line(s.line)
		assert_dict(line).override_failure_message(s.line).is_not_empty()
		assert_str(str(line["role"])).is_equal("computer")
		assert_int(int(line["priority"])).is_equal(1)
		assert_bool(strings.has(s.example)).override_failure_message(s.example).is_true()
		for lang: String in LANGS:
			assert_str(str(line["text"][lang])).is_not_empty()
			assert_str(str(strings[s.example][lang])).is_not_empty()
		if not s.is_pair():
			# The subtitle adds the player's binding of this very control; it is never voiced.
			var slots: Dictionary = line["slots"]
			assert_array(slots.keys()).is_equal(["binding"])
			assert_str(DialogueLines.slot_kind(line, "binding")).is_equal("binding")
			assert_str(DialogueLines.binding_intent(line, "binding")).is_equal(String(s.intent))
			assert_bool(DialogueLines.has_voiced_slots(line)).is_false()
			for lang: String in LANGS:
				assert_bool(str(line["text"][lang]).ends_with(" {binding}")).is_true()


# FT: FT-MIS-039
func test_command_steps_name_a_command_of_their_station() -> void:
	for s: TrainingStepDef in steps.steps:
		if s.kind != TrainingStepDef.Kind.COMMAND:
			continue
		var kind: StringName = StringName(String(s.command).get_slice(":", 0))
		assert_object(SimCommands.make(kind)).override_failure_message(String(kind)).is_not_null()
		assert_str(StationViews.station_of_command(kind)).is_equal(String(s.station))


# FT: FT-MIS-039
func test_pair_steps_cover_the_fifteen_pairs() -> void:
	var pairs: Array[TrainingStepDef] = steps.pairs()
	assert_int(pairs.size()).is_equal(15)
	var defs: DefLibrary = DefLibrary.new()
	for i: int in pairs.size():
		var p: StringName = StringName("p%d" % (i + 1))
		assert_str(String(pairs[i].intent)).is_equal("pair_" + String(p))
		var def: PairDef = defs.get_def(&"PairDef", p) as PairDef
		assert_object(def).is_not_null()
		var want: Array = [String(def.stations[0]), String(def.stations[1])]
		want.sort()
		var got: Array = [String(pairs[i].station), String(pairs[i].partner)]
		got.sort()
		assert_array(got).is_equal(want)
		assert_int(pairs[i].kind).is_equal(TrainingStepDef.Kind.NEXT)


# FT: FT-MIS-039
func test_the_driver_flag_names_match_the_command() -> void:
	for station: String in STATIONS:
		var flag: StringName = TrainingNextCommand.flag_name(StringName(station))
		assert_str(String(flag)).is_equal("train.%s.next" % station)
		assert_str(String(TrainingDriver.next_flag(StringName(station)))).is_equal(String(flag))
