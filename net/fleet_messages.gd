class_name FleetMessages
extends RefCounted
## Payloads of the multi-ship and PvP events (#11, protocol version 8; docs/protocol.md
## "Multi-ship games and PvP"): one builder per event and PAYLOADS, the field types each
## must have, so the server (strand C) builds them and the client (strand D) reads them by
## the same names. check() is the receiving side's guard, as NetProtocol.check() is for
## control messages. Scoreboard rows carry status and progress only: no hull, no
## positions (M4-Q9, FT-NET-010).

## Scoreboard states of a ship (M4-Q9).
const IN_PLAY: String = "in_play"
const FINISHED: String = "finished"
const DESTROYED: String = "destroyed"
## `handover` to_ship when no friendly ship is left: the lobby scoreboard (D91).
const TO_SCOREBOARD: int = -1
## request_rejected reasons for the new requests and the cross-ship takeover.
const FLEET_FULL: String = "fleet_full"
const LOBBY_CLOSED: String = "lobby_closed"
const BAD_TEAM: String = "bad_team"
const BAD_MODE: String = "bad_mode"
const ENEMY_SHIP: String = "enemy_ship"
const TAKEN: String = "taken"
const NO_RELAUNCH: String = "no_relaunch"
## RerollModifier with fewer than two run modifiers to choose from (gp-11).
const NO_REROLL: String = "no_reroll"

## Event type -> field -> Variant type. A row of `fleet.ships` follows FLEET_SHIP and of
## `scoreboard.rows` SCOREBOARD_ROW.
const PAYLOADS: Dictionary = {
	NetProtocol.EVENT_FLEET:
	{
		"ships": TYPE_ARRAY,
		"mode": TYPE_STRING,
		"team_win": TYPE_STRING,
		"lives": TYPE_INT,
		"max_ships": TYPE_INT,
		"waiting": TYPE_ARRAY,
		"started": TYPE_BOOL,
		"host": TYPE_BOOL,
		"modifier": TYPE_STRING,
		"drop_pause": TYPE_BOOL,
		"fill_bots": TYPE_BOOL,
		"rerollable": TYPE_BOOL,
	},
	NetProtocol.EVENT_TAKEOVER:
	{"ship": TYPE_INT, "seat": TYPE_STRING, "by": TYPE_STRING, "from_ship": TYPE_INT},
	NetProtocol.EVENT_HANDOVER: {"ship": TYPE_INT, "to_ship": TYPE_INT},
	NetProtocol.EVENT_SCOREBOARD: {"rows": TYPE_ARRAY},
	NetProtocol.EVENT_ELIMINATED:
	{"ship": TYPE_INT, "reason": TYPE_STRING, "lives": TYPE_INT, "cost": TYPE_INT},
	NetProtocol.EVENT_RELAUNCH_VOTES:
	{"ship": TYPE_INT, "voters": TYPE_ARRAY, "sessions": TYPE_ARRAY, "needed": TYPE_INT},
	NetProtocol.EVENT_RELAUNCHED: {"ship": TYPE_INT, "lives": TYPE_INT},
	NetProtocol.EVENT_GAME_OVER:
	{
		"reason": TYPE_STRING,
		"winners": TYPE_ARRAY,
		"team": TYPE_INT,
		"hold_time": TYPE_FLOAT,
		"time": TYPE_FLOAT,
	},
}
const FLEET_SHIP: Dictionary = {
	"ship": TYPE_INT,
	"name": TYPE_STRING,
	"team": TYPE_INT,
	"seats": TYPE_ARRAY,
	"crew": TYPE_INT,
	"uncovered": TYPE_ARRAY,
	"covered": TYPE_BOOL,
	"started": TYPE_BOOL,
}
const SCOREBOARD_ROW: Dictionary = {
	"ship": TYPE_INT,
	"name": TYPE_STRING,
	"team": TYPE_INT,
	"state": TYPE_STRING,
	"encounters": TYPE_INT,
	"time": TYPE_FLOAT,
	"kills": TYPE_INT,
}


## The `pause` event body (R06-10, one builder for both pauses): a coverage pause of `ship`,
## or the host pause (ship -1, nothing uncovered, crew 0); `host` is always there.
static func pause(ship: int, uncovered: Array, crew: int, min_crew: int, host: bool) -> Dictionary:
	return {
		"ship": ship,
		"uncovered": uncovered.duplicate(),
		"crew": crew,
		"min_crew": min_crew,
		"host": host,
	}


## The `resume` event body of the coverage pause (host false) or the host pause (true).
static func resume(tick: int, host: bool) -> Dictionary:
	return {"tick": tick, "host": host}


## One ship of the multi-ship lobby (M4-Q3, M4-Q4): seats [{name, seat, ready}] as in
## `lobby`, crew and uncovered from NetCoverage, covered when it passes coverage, started once
## the universe started with it.
static func fleet_ship(
	ship: int,
	name: String,
	team: int,
	seats: Array,
	crew: int,
	uncovered: Array,
	covered: bool,
	started: bool
) -> Dictionary:
	return {
		"ship": ship,
		"name": name,
		"team": team,
		"seats": seats,
		"crew": crew,
		"uncovered": uncovered,
		"covered": covered,
		"started": started,
	}


## The multi-ship lobby: every ship, the host's mode and options, the crewed ships not yet
## ready to start (waiting: coverage fails or a crew player isn't Ready, #37 C1), whether the
## universe has started (all together, M4-Q4) and whether a host is connected (`host`: without
## one any Ready crew player may Start). `options` adds the host's options (#40 D1, D2,
## gp-11): `modifier` (a RunModifierDef id, "" for none; its text is modifier.<id>.name and
## .detail), `rerollable` (another modifier to roll), `drop_pause` and `fill_bots`; each
## missing one is its default.
## `mode` and `team_win` are GameRules' names; the server fills them, so this class names
## no sim class and the clients may read it (F4).
static func fleet(
	ships: Array,
	mode: String,
	team_win: String,
	max_ships: int,
	lives: int,
	waiting: Array,
	started: bool,
	host: bool,
	options: Dictionary = {}
) -> Dictionary:
	return {
		"modifier": str(options.get("modifier", "")),
		"drop_pause": bool(options.get("drop_pause", false)),
		"fill_bots": bool(options.get("fill_bots", false)),
		"rerollable": bool(options.get("rerollable", false)),
		"ships": ships,
		"mode": mode,
		"team_win": team_win,
		"lives": lives,
		"max_ships": max_ships,
		"waiting": waiting,
		"started": started,
		"host": host,
	}


## A session took over `seat` on `ship` during its pause (M4-Q8): `by` its name, from_ship
## the ship it came from (the same ship for its Captain or a viewer).
static func takeover(ship: int, seat: String, by: String, from_ship: int) -> Dictionary:
	return {"ship": ship, "seat": seat, "by": by, "from_ship": from_ship}


## An eliminated session now views to_ship's main screen, or TO_SCOREBOARD (FT-MIS-030, D91).
static func handover(ship: int, to_ship: int) -> Dictionary:
	return {"ship": ship, "to_ship": to_ship}


static func scoreboard_row(
	ship: int, name: String, team: int, state: String, encounters: int, time: float, kills: int
) -> Dictionary:
	return {
		"ship": ship,
		"name": name,
		"team": team,
		"state": state,
		"encounters": encounters,
		"time": time,
		"kills": kills,
	}


static func scoreboard(rows: Array) -> Dictionary:
	return {"rows": rows}


## lives: the relaunches the ship's side has left, -1 for unlimited.
## cost: the credits a relaunch takes from the ship's purse (gp-10; 0 free).
static func eliminated(ship: int, reason: String, lives: int, cost: int = 0) -> Dictionary:
	return {"ship": ship, "reason": reason, "lives": lives, "cost": cost}


static func relaunched(ship: int, lives: int) -> Dictionary:
	return {"ship": ship, "lives": lives}


## The game's outcome (GameOutcome: its reason name, winners and the lobby team of its
## winner_faction, NetFleet.team_of_faction); time: the session's length; hold_time: HOLDOUT's
## score, how long the finite side lasted.
static func game_over(
	reason: String, winners: Array, team: int, hold_time: float, time: float
) -> Dictionary:
	return {
		"reason": reason,
		"winners": winners,
		"team": team,
		"hold_time": hold_time,
		"time": time,
	}


## Why an event's payload doesn't match its shape, or "" if it does (rows included).
static func check(type: String, payload: Dictionary) -> String:
	if not PAYLOADS.has(type):
		return "unknown event %s" % type
	var why: String = _check_shape(type, payload, PAYLOADS[type])
	if why != "":
		return why
	var rows_key: String = ""
	var row_shape: Dictionary = {}
	if type == NetProtocol.EVENT_FLEET:
		rows_key = "ships"
		row_shape = FLEET_SHIP
	elif type == NetProtocol.EVENT_SCOREBOARD:
		rows_key = "rows"
		row_shape = SCOREBOARD_ROW
	if rows_key == "":
		return ""
	for row: Variant in payload[rows_key]:
		if not row is Dictionary:
			return "%s: a row is not a Dictionary" % type
		why = _check_shape(type, row, row_shape)
		if why != "":
			return why
	return ""


static func _check_shape(type: String, d: Dictionary, shape: Dictionary) -> String:
	if d.size() != shape.size():
		return "%s: %d fields, expected %d" % [type, d.size(), shape.size()]
	for key: Variant in d:
		if not key is String or not shape.has(key):
			return "%s: unknown field %s" % [type, key]
		if typeof(d[key]) != shape[key]:
			return "%s: field %s has type %d" % [type, key, typeof(d[key])]
	return ""
