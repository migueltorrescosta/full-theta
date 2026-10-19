class_name CommandLog
extends RefCounted
## A replayable record of a run (FT-ARC-008, FT-TST-009): the seed, the build id, the
## setup parameters that rebuild the starting world (for M1: the player ShipDef id and
## the EnemyDef id) and every accepted crew command with the tick it was applied on, in
## application order. A fresh world built from the same setup, with each command
## submitted right before the step of its tick, reproduces the run on the same build and
## platform. Pure: the caller does any file I/O with to_text() and from_text().
##
## Text format, one `key=value # echo` line per item. The value is the Variant in
## var_to_bytes() encoding, base64: it holds every float bit for bit (64-bit scalars,
## 32-bit Vector3 components, -0.0 included), which var_to_str() does not on Godot 4.7.2
## (str_to_var(var_to_str(x)) changes most 64-bit floats in their last bits). The echo
## after " # " is var_to_str() of the same value for readers and diffs; loading
## ignores it.

const HEADER: String = "# Full Theta command log (FT-ARC-008)"
const FORMAT: int = 1

var seed_value: int = 0
var build_id: String = ""
## Inputs that rebuild the starting world, e.g. {"player": &"m1_corvette",
## "enemy": &"m1_raider"}; values must survive var_to_bytes() (no objects).
var setup: Dictionary = {}
## Accepted commands as SimCommand.to_dict() (each with its "tick"), in application
## order.
var entries: Array[Dictionary] = []


## The log of a world's run so far: its seed, build id and world.command_log.
static func from_world(world: SimWorld, setup_params: Dictionary = {}) -> CommandLog:
	var out: CommandLog = CommandLog.new()
	out.seed_value = world.seed_value
	out.build_id = world.build_id
	out.setup = setup_params.duplicate(true)
	for c: SimCommand in world.command_log:
		out.entries.append(c.to_dict())
	return out


## Fresh command objects for the entries, each holding its recorded tick.
func commands() -> Array[SimCommand]:
	var out: Array[SimCommand] = []
	for d: Dictionary in entries:
		out.append(SimCommands.from_dict(d))
	return out


func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray([HEADER])
	lines.append(_line("format", FORMAT))
	lines.append(_line("seed", seed_value))
	lines.append(_line("build", build_id))
	lines.append(_line("setup", setup))
	for d: Dictionary in entries:
		lines.append(_line("command", d))
	return "\n".join(lines) + "\n"


## Parses to_text() output; null if the text is malformed, of another format or holds a
## command kind SimCommands doesn't know.
static func from_text(text: String) -> CommandLog:
	var parsed: CommandLog = CommandLog.new()
	var seen: Dictionary[String, bool] = {}
	for raw: String in text.split("\n", false):
		if raw.begins_with("#"):
			continue
		var eq: int = raw.find("=")
		if eq < 0:
			return null
		var key: String = raw.substr(0, eq)
		var value: Variant = _decode(raw.substr(eq + 1).get_slice(" ", 0))
		if not parsed._set_item(key, value):
			return null
		seen[key] = true
	if not (seen.has("format") and seen.has("seed") and seen.has("build")):
		return null
	return parsed


## Replays this log on a freshly built world, stepping until world.tick == end_tick:
## each command is submitted right before the step whose tick equals its recorded tick,
## so it applies on that tick (FT-TST-009). Returns the problems found, empty when every
## command up to end_tick was accepted and stamped with its recorded tick.
func replay(world: SimWorld, end_tick: int) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var cmds: Array[SimCommand] = commands()
	var i: int = 0
	while world.tick < end_tick:
		var t: int = world.tick
		var batch: Array[SimCommand] = []
		var expected: Array[bool] = []
		while i < cmds.size() and cmds[i].tick <= t:
			if cmds[i].tick < t:
				problems.append("command %d (%s) for tick %d is late" % [i, entries[i], t])
			else:
				batch.append(cmds[i])
				expected.append(cmds[i].accepted)
			world.submit(cmds[i])
			i += 1
		var logged: int = world.command_log.size()
		world.step()
		var applied: Array[SimCommand] = world.command_log.slice(logged)
		for k: int in batch.size():
			var c: SimCommand = batch[k]
			if not applied.has(c) or c.tick != t or c.accepted != expected[k]:
				problems.append("command %s not applied on tick %d as recorded" % [c.to_dict(), t])
	return problems


func _set_item(key: String, value: Variant) -> bool:
	match key:
		"format":
			return value is int and value == FORMAT
		"seed" when value is int:
			seed_value = value
		"build" when value is String:
			build_id = value
		"setup" when value is Dictionary:
			setup = value
		"command" when value is Dictionary:
			if SimCommands.make(StringName(value.get("kind", ""))) == null:
				return false
			entries.append(value)
		_:
			return false
	return true


static func _line(key: String, value: Variant) -> String:
	var echo: String = var_to_str(value).replace("\n", " ")
	return "%s=%s # %s" % [key, Marshalls.raw_to_base64(var_to_bytes(value)), echo]


static func _decode(b64: String) -> Variant:
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	return bytes_to_var(bytes) if bytes.size() >= 4 else null
