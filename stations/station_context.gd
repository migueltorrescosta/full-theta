class_name StationContext
extends RefCounted
## Everything a station screen and its panels read and send through, built once per
## connection by ClientShell (or by tests/stations/station_fixture.gd with no server):
## the snapshot view and its interpolation, the CrewState model, the send seam, the
## player's settings and bindings, the input matcher and a clock.

## The connected client, or null in fixtures. Panels send through `intents`, not this.
var client: NetClient = null
var intents: ShipIntents = ShipIntents.new()
var crew: CrewState = CrewState.new()
## Snapshot state (NetClient.view, or a fixture's).
var view: NetViewState = NetViewState.new()
var interp: SnapshotInterpolator = SnapshotInterpolator.new()
var settings: ClientSettings = ClientSettings.new()
var matcher: InputMatcher = InputMatcher.new()
## Milliseconds; fixtures pin it.
var clock: Callable = Time.get_ticks_msec


func now_ms() -> int:
	return int(clock.call())


## The shared selection's offset from the own ship in the ship frame (m), or null when
## nothing is selected or its position is unknown (a site without data).
func selection_local() -> Variant:
	var s: Dictionary = crew.selection
	match s.get("kind", ""):
		"contact":
			if int(s["id"]) not in interp.contact_ids():
				return null
			return interp.local(interp.offset_to(interp.contact_position(int(s["id"]))))
		"mark":
			var m: Dictionary = crew.mark_in_slot(int(s["id"]))
			if m.is_empty():
				return null
			return interp.local(interp.offset_to(mark_position(m)))
	return null


## A mark's site-local position (m): its contact's position plus the stored offset
## when attached, else its own position.
func mark_position(m: Dictionary) -> Vector3:
	var contact: int = int(m.get("contact", -1))
	if contact >= 0 and contact in interp.contact_ids():
		return interp.contact_position(contact) + (m["pos"] as Vector3)
	return m["pos"]
