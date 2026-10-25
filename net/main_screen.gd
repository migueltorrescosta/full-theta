class_name MainScreen
extends RefCounted
## The main screen's view and who may switch it (FT-MSC-002, FT-MSC-005, FT-CPT-001,
## FT-RLY-010, D54, D60, D88). Server rules and view ids shared with the client; the
## state itself (one view per ship) lives in NetCrewState, outside the sim like marks.

## The views, in the order of the Captain's buttons and keys 1 to 5 (Relay: Alt+1 to 5).
enum View { FORWARD, CHASE, TACTICAL, TARGET, STATUS }

## Names for the i18n keys `view.<name>` and the `main_view` event.
const NAMES: Array[String] = ["forward", "chase", "tactical", "target", "status"]

## Refusals (request_rejected reason).
const BAD_VIEW: String = "bad_view"
## A Captain is seated (counting reconnect grace): only the Captain switches.
const CAPTAIN_SEATED: String = "captain_seated"


## Why a pick of `role` may not switch the view, or "": the Captain always may; Relay
## only while no Captain is seated; everyone else never (FT-MSC-005). `captain_seated`
## counts a Captain within reconnect grace.
static func rule(role: CrewMarks.Role, view: int, captain_seated: bool) -> String:
	if view < 0 or view >= NAMES.size():
		return BAD_VIEW
	match role:
		CrewMarks.Role.CAPTAIN:
			return ""
		CrewMarks.Role.RELAY:
			return CAPTAIN_SEATED if captain_seated else ""
	return CommandGate.NOT_ALLOWED
