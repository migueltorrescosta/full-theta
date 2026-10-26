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
## The host's own server: the address it listens on and its WebSocket port, for the
## lobby's join info; "" for a player who joined someone else's game.
var host_bind: String = ""
var host_port: int = 0
var matcher: InputMatcher = InputMatcher.new()
## Milliseconds; fixtures pin it.
var clock: Callable = Time.get_ticks_msec

## Contact id -> last seen position (m), for marks attached to a lost contact.
var _last_seen: Dictionary = {}
var _picture: ContactPicture = null
var _picture_key: Array = []
var _ship_def: ShipDef = null
var _ship_def_path: String = ""


func now_ms() -> int:
	return int(clock.call())


## The radar picture (ContactPicture) for this frame: rebuilt when the frame, the clock,
## the interpolated state, the marks or the pings changed.
func picture() -> ContactPicture:
	var key: Array = [
		Engine.get_process_frames(),
		now_ms(),
		interp.revision,
		crew.marks.duplicate(true),
		crew.pings.duplicate(true),
		crew.zones.duplicate(true),
		crew.sites.duplicate(true),
	]
	if _picture == null or _picture.interp != interp or key != _picture_key:
		_picture = ContactPicture.build(self)
		_picture_key = key
	return _picture


## The own ship's ShipDef (content/ships/<def>.tres from the catalogue), or null.
func ship_def() -> ShipDef:
	for s: Dictionary in crew.catalogue.get("ships", []):
		if int(s.get("id", -1)) != crew.ship:
			continue
		var path: String = "res://content/ships/%s.tres" % str(s.get("def", ""))
		if path != _ship_def_path:
			_ship_def_path = path
			_ship_def = load(path) as ShipDef if ResourceLoader.exists(path) else null
		return _ship_def
	return null


## Places a new mark (slot -1: the first free one) or replaces `slot` on an item as
## item_at returns it: on a contact (attached) or a map point.
func mark_item(slot: int, item: Dictionary) -> void:
	if item.get("kind", "") == "contact":
		intents.place_mark(slot, "", int(item["id"]), Vector3.ZERO)
	elif item.get("kind", "") == "point":
		intents.place_mark(slot, "", -1, item["pos"])


## Places a mark (slot -1: the first free one) on one of a contact's scanned subsystems
## (FT-SPA-014, D202): an attached mark's x names the subsystem as its ShipDef.subsystems
## index plus one; the server refuses it until a scan revealed that weak point.
func mark_subsystem(slot: int, contact: int, subsystem: int) -> void:
	intents.place_mark(slot, "", contact, Vector3(float(subsystem + 1), 0.0, 0.0))


## Moves mark `slot` onto a contact (attached) or a map point.
func move_mark_to(slot: int, item: Dictionary) -> void:
	if item.get("kind", "") == "contact":
		intents.move_mark(slot, int(item["id"]), Vector3.ZERO)
	elif item.get("kind", "") == "point":
		intents.move_mark(slot, -1, item["pos"])


## Pings an item (contact, mark) or a map point.
func ping_item(item: Dictionary) -> void:
	if item.get("kind", "") == "point":
		intents.ping("point", -1, item["pos"])
	elif not item.is_empty():
		intents.ping(item["kind"], int(item["id"]), Vector3.ZERO)


## The shared selection's offset from the own ship in the ship frame (m), or null when
## nothing is selected or its position is unknown (no data).
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
		"zone":
			var at: Variant = zone_position(int(s["id"]))
			return null if at == null else interp.local(interp.offset_to(at as Vector3))
	return null


## The position (m) of a zone item, or null: a marked zone (id 0 and up), a
## deployed probe's bubble (id -1 - serial) or a sim hazard (id -1000 - hazard id) the
## faction knows (D222, D208).
func zone_position(id: int) -> Variant:
	if id >= 0:
		var z: Dictionary = crew.zone_by_id(id)
		return null if z.is_empty() else z["pos"]
	var relay: Dictionary = view.blocks.get(StationViews.Section.RELAY, {})
	if id <= -1000:
		for h: Dictionary in relay.get("hazards", []):
			if -1000 - int(h["id"]) == id:
				return h["pos"]
	else:
		for p: Dictionary in relay.get("probes", []):
			if bool(p["deployed"]) and -1 - int(p["serial"]) == id:
				return p["pos"]
	return null


## A mark's position (m): its contact's position plus the stored offset
## when attached (the contact's last known position once it is lost,
## docs/protocol.md), else its own position.
func mark_position(m: Dictionary) -> Vector3:
	var contact: int = int(m.get("contact", -1))
	if contact < 0:
		return m["pos"]
	if contact in interp.contact_ids():
		_last_seen[contact] = interp.contact_position(contact)
	return _last_seen.get(contact, interp.own_position()) + (m["pos"] as Vector3)
