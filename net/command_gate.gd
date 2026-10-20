class_name CommandGate
extends RefCounted
## Validates a client's Command{seq, cmd} before it reaches the sim (FT-NET-006): the
## sender has a pick, is within its rate limit, names a crew command kind whose station
## its pick covers (station holding), for its own ship, with known fields of the right
## types and finite values; then the claims hook (ServerSession.claim_rule). Game rules
## are the sim's: a command the sim rejects on apply becomes CommandRejected{reason:
## sim_rejected} (ServerSession.after_ticks). Every rejection is a CommandRejected event to the
## sender only (FT-NET-007).

const NO_PICK: String = "no_pick"
const RATE_LIMITED: String = "rate_limited"
const UNKNOWN_KIND: String = "unknown_kind"
const NOT_ALLOWED: String = "not_allowed"
const NOT_YOUR_STATION: String = "not_your_station"
const WRONG_SHIP: String = "wrong_ship"
const BAD_FIELD: String = "bad_field"
const BAD_VALUE: String = "bad_value"
const SIM_REJECTED: String = "sim_rejected"
const SHIP_DESTROYED: String = "ship_destroyed"
## Another player holds the item the command acts on (FT-NET-023).
const CLAIMED: String = "claimed"
## A mid-run catalogue change that would make the ship fail coverage (FT-NET-043);
## sent with seq -1 (the Pick or Release had none).
const BREAKS_COVERAGE: String = "breaks_coverage"
## The sender's ship was abandoned (FT-NET-041).
const SHIP_ABANDONED: String = "ship_abandoned"

## Fields the server sets, never the client (ship_id may be sent, if it is the sender's).
const SERVER_FIELDS: Array[String] = ["kind", "ship_id", "tick", "accepted"]


## Returns [SimCommand, ""] for a valid command (ship and source set), or [null,
## reason]. claims is Callable(session, command) -> reason or "" (ServerSession).
static func check(
	session: NetSession, cmd: Dictionary, now_us: int, claims: Callable = Callable()
) -> Array:
	if not session.has_pick():
		return [null, NO_PICK]
	if not session.bucket.take(now_us):
		return [null, RATE_LIMITED]
	var kind_value: Variant = cmd.get("kind")
	if not (kind_value is String or kind_value is StringName):
		return [null, UNKNOWN_KIND]
	var kind: StringName = StringName(kind_value)
	var command: SimCommand = SimCommands.make(kind)
	if command == null:
		return [null, UNKNOWN_KIND]
	var station: String = StationViews.station_of_command(kind)
	if station == "":
		return [null, NOT_ALLOWED]
	if not StationViews.stations_of(session.entry).has(station):
		return [null, NOT_YOUR_STATION]
	if cmd.has("ship_id") and not (cmd["ship_id"] is int and cmd["ship_id"] == session.ship):
		return [null, WRONG_SHIP]
	var template: Dictionary = command.to_dict()
	var fields: Dictionary = {}
	for key: Variant in cmd:
		if not key is String:
			return [null, BAD_FIELD]
		if SERVER_FIELDS.has(key):
			continue
		if not template.has(key):
			return [null, BAD_FIELD]
		var value: Variant = _coerce(cmd[key], typeof(template[key]))
		if typeof(value) != typeof(template[key]):
			return [null, BAD_FIELD]
		if not _finite(value):
			return [null, BAD_VALUE]
		fields[key] = value
	command.set_from_dict(fields)
	command.ship_id = session.ship
	command.source = SimCommand.Source.CREW
	if claims.is_valid():
		var reason: String = claims.call(session, command)
		if reason != "":
			return [null, reason]
	return [command, ""]


## Accepts an int for a float field and a String for a StringName field.
static func _coerce(value: Variant, want: int) -> Variant:
	if want == TYPE_FLOAT and value is int:
		return float(value)
	if want == TYPE_STRING_NAME and value is String:
		return StringName(value)
	return value


static func _finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR3:
			return (value as Vector3).is_finite()
		TYPE_QUATERNION:
			return (value as Quaternion).is_finite()
	return true
