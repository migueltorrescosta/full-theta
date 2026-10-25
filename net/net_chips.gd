class_name NetChips
extends RefCounted
## Request chips (spec §7.4, FT-PAIR-009, FT-PAIR-012, FT-PAIR-013, FT-PAIR-021, D191):
## a cue one station sends another ("boost", "bring mount 2 to bear"). The list of chips is
## data (content/chips/chips.tres); a chip does nothing in the sim, it tells the other
## player what the sender wants, so the server never creates one: only a CHIP message from
## a player does (FT-PAIR-012). Chips share one expiry (CUE): an unanswered chip goes away
## silently and is counted for the debrief, not announced. The open chips of a ship are
## Section.CHIPS (ChipsSection), each posted to the net thread when the list changes.
## Messages: CHIP{op "send", chip, arg} from a station that can send the chip, and CHIP{op
## "answer", id, accept} from a station that receives it. Crew state outside the sim, like
## marks (D171); a run reset clears it.

## request_rejected reasons.
const OFF: String = "chips_off"
const BAD_CHIP: String = "bad_chip"
const INERT: String = "chip_inert"
const NOT_YOURS: String = "chip_not_yours"
const SAME_SCREEN: String = "chip_same_screen"
const NOBODY: String = "chip_nobody"
const ALREADY_OPEN: String = "chip_open"
const FULL: String = "chips_full"
const BAD_ARG: String = "chip_bad_arg"
const BAD_ID: String = "chip_bad_id"

## The chip list, loaded once (read-only after).
static var _def: ChipsDef = load("res://content/chips/chips.tres") as ChipsDef

## The owning session, held weakly (it owns this object).
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession

var _session: WeakRef
## Ship -> open chips: {id, chip (index in ChipsDef.chips), arg, from, to (indices in
## StationViews.CREW), sent, expires (sim ticks), by (session id)}.
var _open: Dictionary[int, Array] = {}
var _dirty: Dictionary[int, bool] = {}
var _next_id: int = 1


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)


static func def() -> ChipsDef:
	return _def


## The index of a chip id in the list, or -1.
static func index_of(chip_id: String) -> int:
	for i: int in _def.chips.size():
		if String(_def.chips[i].id) == chip_id:
			return i
	return -1


## What the chip's argument names (ChipDef.Arg), NONE for an unknown chip.
static func arg_kind(chip_id: String) -> ChipDef.Arg:
	var at: int = index_of(chip_id)
	return _def.chips[at].arg if at >= 0 else ChipDef.Arg.NONE


## Chip{op, ...}.
func on_chip(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var why: String
	if msg["op"] == "send":
		why = send(s, msg["chip"], msg["arg"])
	elif msg["op"] == "answer":
		why = answer(s, msg["id"], msg["accept"])
	else:
		why = BAD_CHIP
	if why != "":
		session.request_rejected(
			s, NetProtocol.Type.CHIP, why, {"op": msg["op"], "chip": msg["chip"]}
		)


## Opens a chip from the session's station to the chip's receiver; the reason it can't, or "".
func send(s: NetSession, chip_id: String, arg: int) -> String:
	var why: String = _sender_rule(s)
	var at: int = index_of(chip_id)
	if why == "" and at < 0:
		why = BAD_CHIP
	if why == "":
		why = _chip_rule(s, _def.chips[at], arg)
	var chip: ChipDef = _def.chips[at] if at >= 0 else null
	var open: Array = _open.get_or_add(s.ship, [])
	if why == "":
		why = _open_rule(open, at, arg_of(chip, arg))
	if why != "":
		return why
	var tick: int = session.world.tick
	var row: Dictionary = {
		"id": _next_id,
		"chip": at,
		"arg": arg_of(chip, arg),
		"from": StationViews.CREW.find(String(chip.from_station)),
		"to": StationViews.CREW.find(String(chip.to_station)),
		"sent": tick,
		"expires": tick + ceili(_def.expiry_s * SimWorld.HZ),
		"by": s.id,
	}
	_next_id = (_next_id + 1) & 0xffff
	open.append(row)
	_dirty[s.ship] = true
	session.coop.record(CoopEvents.CHIP_SENT, chip.pair, s.ship, {"chip": String(chip.id)})
	return ""


## The receiver answers (accept or decline) a chip of its ship; the reason it can't, or "".
## An answered chip closes and is told to the sender; accepting counts as a cooperative
## event, declining does not.
func answer(s: NetSession, id: int, accept: bool) -> String:
	if not s.has_pick() or not StationViews.is_crew(s.entry):
		return ServerSession.NOT_CREW
	var open: Array = _open.get(s.ship, [])
	for i: int in open.size():
		var row: Dictionary = open[i]
		if row["id"] != id:
			continue
		var chip: ChipDef = _def.chips[row["chip"]]
		if not StationViews.stations_of(s.entry).has(String(chip.to_station)):
			return NOT_YOURS
		open.remove_at(i)
		_dirty[s.ship] = true
		var kind: String = CoopEvents.CHIP_ANSWERED if accept else CoopEvents.CHIP_DECLINED
		session.coop.record(kind, chip.pair, s.ship, {"chip": String(chip.id)})
		_tell_sender(s.ship, row, accept, s.name)
		return ""
	return BAD_ID


## Drops the chips whose time ran out, silently: no event reaches a player, the count goes
## to the debrief (FT-PAIR-013). Posts the lists that changed. Call once per frame.
func step() -> void:
	var tick: int = session.world.tick
	for ship: int in _open:
		var open: Array = _open[ship]
		for i: int in range(open.size() - 1, -1, -1):
			if tick >= int(open[i]["expires"]):
				var chip: ChipDef = _def.chips[open[i]["chip"]]
				session.coop.record(
					CoopEvents.CHIP_EXPIRED, chip.pair, ship, {"chip": String(chip.id)}
				)
				open.remove_at(i)
				_dirty[ship] = true
	for ship: int in _dirty:
		session.transport.post_chips(ship, rows_of(ship))
	_dirty.clear()


## The ship's open chips as CHIPS rows (without the sender).
func rows_of(ship: int) -> Array:
	var out: Array = []
	for row: Dictionary in _open.get(ship, []):
		var r: Dictionary = row.duplicate()
		r.erase("by")
		out.append(r)
	return out


## Open chips of a ship (tests): the rows with their sender.
func open_of(ship: int) -> Array:
	return (_open.get(ship, []) as Array).duplicate(true)


## A run reset: every chip goes (the new world starts without any).
func reset(ship: int) -> void:
	_open.erase(ship)
	_dirty[ship] = true


## The argument a chip carries: -1 for a chip without one.
static func arg_of(chip: ChipDef, arg: int) -> int:
	return arg if chip.arg != ChipDef.Arg.NONE else -1


## The sender is a crew pick and the chips toggle of its view is on (FT-PAIR-009).
func _sender_rule(s: NetSession) -> String:
	var why: String = ""
	var picked: DataToggles = DataToggles.parse(s.toggles)
	if not s.has_pick() or not StationViews.is_crew(s.entry):
		why = ServerSession.NOT_CREW
	elif picked == null or not picked.on(ViewFilter.CHIPS):
		why = OFF
	return why


## The chip may go from this session to its receiver: active, from a station the session
## holds and not to one it holds too (a joint view runs it as a direct action), with a
## sensible argument and a player at the receiving station.
func _chip_rule(s: NetSession, chip: ChipDef, arg: int) -> String:
	var stations: Array[String] = StationViews.stations_of(s.entry)
	var why: String = ""
	if not chip.active:
		why = INERT
	elif stations.has(String(chip.to_station)):
		why = SAME_SCREEN
	elif not stations.has(String(chip.from_station)):
		why = NOT_YOURS
	elif not _arg_ok(s.ship, chip, arg):
		why = BAD_ARG
	elif not _someone_holds(s.ship, chip.to_station):
		why = NOBODY
	return why


## Room for one more chip, and not the same one twice.
func _open_rule(open: Array, at: int, arg: int) -> String:
	if open.size() >= _def.max_open:
		return FULL
	for row: Dictionary in open:
		if row["chip"] == at and row["arg"] == arg:
			return ALREADY_OPEN
	return ""


func _arg_ok(ship: int, chip: ChipDef, arg: int) -> bool:
	var world: SimWorld = session.world
	match chip.arg:
		ChipDef.Arg.MOUNT:
			return arg >= 0 and arg < world.defs[ship].mounts.size()
		ChipDef.Arg.CONTACT:
			var faction: int = world.faction_of(ship)
			return (
				arg >= 0
				and arg < world.ship_count()
				and KnowledgeSystem.is_detected(world, faction, arg)
			)
	return true


## Whether a connected crew session of the ship holds the station.
func _someone_holds(ship: int, station: StringName) -> bool:
	for s: NetSession in session.by_id.values():
		if s.ship == ship and s.connected() and StationViews.stations_of(s.entry).has(station):
			return true
	return false


func _tell_sender(ship: int, row: Dictionary, accept: bool, by: String) -> void:
	var sender: NetSession = session.by_id.get(row["by"])
	if sender != null and sender.ship == ship:
		session.notify(
			sender,
			NetProtocol.EVENT_CHIP_ANSWER,
			{
				"chip": String(_def.chips[row["chip"]].id),
				"arg": row["arg"],
				"accept": accept,
				"by": by
			}
		)
