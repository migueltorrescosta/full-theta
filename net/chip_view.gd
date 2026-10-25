class_name ChipView
extends RefCounted
## Client side of Section.CHIPS: the open request chips of the ship, decoded from the view's
## block (NetViewState.blocks[Section.CHIPS]) into rows that name stations and chips. The
## Captain's chip list and every station's chip strip read the chips through open_chips().

## Sim ticks per second, for the time a chip has left.
const HZ: int = SimWorld.HZ


## Every chip the view lists, oldest first: {id: int, chip: String (chips.tres id), arg: int
## (mount index or contact id, -1 for none), from: String, to: String (station ids), sent:
## int, expires: int (sim ticks)}. A crew view lists the chips its stations send or receive,
## the Captain, the Viewer and the dev entry all of the ship's.
static func open_chips(view: NetViewState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: ChipsDef = NetChips.def()
	for row: Dictionary in view.blocks.get(StationViews.Section.CHIPS, {}).get("chips", []):
		var at: int = row["chip"]
		if at < 0 or at >= def.chips.size():
			continue
		(
			out
			. append(
				{
					"id": row["id"],
					"chip": String(def.chips[at].id),
					"arg": row["arg"],
					"from": StationViews.CREW[row["from"]],
					"to": StationViews.CREW[row["to"]],
					"sent": row["sent"],
					"expires": row["expires"],
				}
			)
		)
	return out


## The chips addressed to any of the stations, oldest first.
static func incoming(view: NetViewState, stations: Array) -> Array[Dictionary]:
	return open_chips(view).filter(func(c: Dictionary) -> bool: return stations.has(c["to"]))


## The chips sent by any of the stations (and not to one of them), oldest first.
static func outgoing(view: NetViewState, stations: Array) -> Array[Dictionary]:
	return open_chips(view).filter(
		func(c: Dictionary) -> bool: return stations.has(c["from"]) and not stations.has(c["to"])
	)


## Seconds a chip has left at the view's tick (never below 0).
static func left_s(view: NetViewState, chip: Dictionary) -> float:
	return maxf(0.0, float(int(chip["expires"]) - view.tick) / float(HZ))


## The chip's text in the session language ("Bring mount 2 to bear"): `callsign` names the
## contact of a chip that carries one.
static func label(chip: Dictionary, callsign: String = "") -> String:
	var text: String = TranslationServer.translate("chip." + str(chip["chip"]))
	match NetChips.arg_kind(str(chip["chip"])):
		ChipDef.Arg.MOUNT:
			return text % (int(chip["arg"]) + 1)
		ChipDef.Arg.CONTACT:
			return text % callsign
	return text
