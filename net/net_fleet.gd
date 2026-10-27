class_name NetFleet
extends RefCounted
## The multi-ship lobby and the PvP session rules on the server (#11, E11, E12; owner M4-Q3,
## M4-Q4, M4-Q6, M4-Q8, M4-Q9, M4-Q10, 2026-10-28). ServerSession owns one and registers its
## handlers. It holds the lobby's ships (ShipSlot) and the host's SessionRules, answers
## ShipAdd, ShipTeam, SessionMode and Relaunch, and builds the `fleet`, `scoreboard`,
## `handover`, `eliminated` and `session_over` payloads (FleetMessages).
## - ShipAdd: any player, up to SessionRules.MAX_SHIPS; a ship nobody picked vanishes at Start.
## - ShipTeam: a session on the ship puts it on team 0 or 1 (TEAMS, HOLDOUT), until Start.
## - SessionMode: host only, until Start.
## - Start: the universe starts once every crewed ship has pressed Start (all together).
## - Takeover in a pause (takeover_rule): allies and the ship's own Captain and viewers, first
##   claim wins, refused if it breaks the taker's own ship's coverage, never enemies.
## - Relaunch: a vote of the eliminated ship's crew, when its side's policy allows.
##
## CONTRACT STUB (strand C): every request is refused `not_implemented`; the lobby keeps the
## server's one fixed set of ships.

var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession
## The lobby's ships, by lobby ship id (slot order).
var slots: Array[ShipSlot] = []
## The host's mode and options.
var rules: SessionRules = SessionRules.new()

var _session: WeakRef


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)
	for type: int in [
		NetProtocol.Type.SHIP_ADD,
		NetProtocol.Type.SHIP_TEAM,
		NetProtocol.Type.SESSION_MODE,
		NetProtocol.Type.RELAUNCH,
	]:
		server_session.add_handler(type, _on_unimplemented)


## The slots RunSetup builds at Start: those with at least one pick, in lobby order.
## Stub: every slot.
func start_slots() -> Array[ShipSlot]:
	return slots.duplicate()


## Why `s` may not take over `entry` on the paused `ship`, or "" (M4-Q8, FT-NET-042):
## FleetMessages.ENEMY_SHIP, TAKEN or BREAKS_COVERAGE, or ServerSession's reasons.
## Stub: ServerSession.NOT_IMPLEMENTED.
func takeover_rule(_s: NetSession, _ship: int, _entry: String) -> String:
	return ServerSession.NOT_IMPLEMENTED


## Where an eliminated ship's sessions go: a surviving friendly ship's id, or
## FleetMessages.TO_SCOREBOARD (FT-MIS-030, D91, SessionRules.eliminated_to).
## Stub: the scoreboard.
func destination_of(_ship: int) -> int:
	return FleetMessages.TO_SCOREBOARD


## The live scoreboard's rows (FleetMessages.scoreboard_row, M4-Q9). Stub: none.
func scoreboard_rows() -> Array:
	return []


func _on_unimplemented(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var extra: Dictionary = msg.duplicate()
	extra.erase("t")
	session.request_rejected(s, msg["t"], ServerSession.NOT_IMPLEMENTED, extra)
