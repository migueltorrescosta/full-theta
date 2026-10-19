class_name ContactPicture
extends RefCounted
## The radar's item list from the interpolated snapshot and the crew model: contacts
## (callsign, allegiance from the prefix, ship-frame offset), marks (diamonds; attached
## ones follow their contact) and ping pulses, offsets relative to the own ship
## (minimum image, D124). Point pings (no item) come as kind "point" items: the radar
## draws only their pulse and never selects them. The own ship is the disc centre, not
## an item.


static func build(ctx: StationContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var interp: SnapshotInterpolator = ctx.interp
	var now: int = ctx.now_ms()
	var info: Dictionary = ctx.view.contacts.get("info", {})
	for id: int in interp.contact_ids():
		if id == ctx.crew.ship:
			continue
		var callsign: String = ctx.view.callsign(id)
		var letter: String = Palette.allegiance(callsign)
		# Own-faction ships carry their ship name, no prefix: friendly.
		if int(info.get(id, [0])[0]) & ContactsSection.FLAG_OWN:
			letter = "F"
		var local: Vector3 = _local(interp, interp.contact_position(id))
		out.append(
			_item("contact", id, callsign, letter, local, ctx.crew.pulse("contact", id, now))
		)
	for m: Dictionary in ctx.crew.marks:
		var slot: int = m["slot"]
		var local: Vector3 = _local(interp, ctx.mark_position(m))
		out.append(_item("mark", slot, m["name"], "", local, ctx.crew.pulse("mark", slot, now)))
	for p: Dictionary in ctx.crew.live_pings(now):
		if p["kind"] == "point":
			var pulse: float = 1.0 - float(now - int(p["at_ms"])) / float(CrewState.PING_MS)
			out.append(_item("point", -1, "", "", _local(interp, p["pos"]), pulse))
	return out


static func _local(interp: SnapshotInterpolator, pos: Vector3) -> Vector3:
	return interp.local(interp.offset_to(pos))


static func _item(
	kind: String, id: int, label: String, letter: String, local: Vector3, pulse: float
) -> Dictionary:
	return {
		"kind": kind, "id": id, "label": label, "allegiance": letter, "local": local, "pulse": pulse
	}
