class_name ContactPicture
extends RefCounted
## The radar's item list from the interpolated snapshot and the crew model: contacts
## (callsign, allegiance from the prefix), marks (diamonds; attached ones follow their
## contact) and ping pulses. Each item carries its minimum-image offset from the own
## ship in world axes ("world") and the same offset in the ship frame ("local", D124).
## Point pings (no item) come as kind "point" items: the radar draws only their pulse
## and never selects them. The own ship is the disc centre, not an item. Stations read
## it through StationContext.picture(), built once per frame.

## {"kind": "contact" | "mark" | "zone" | "point", "id", "label", "allegiance" ("H", "U", "F",
## "N", "" own), "world" (Vector3, m), "local" (Vector3, m), "pulse" (0..1)}; "zone" items
## also hold "zone" ("hazard" | "scan") and "radius" (m); every item holds "copies", the
## names of the stations that copied its live ping.
var items: Array[Dictionary] = []
## The own site's name as a callout layer on every station (FT-SPA-027, D98): {"kind":
## "site", "id", "label", "pulse"}, or {} when the scenario names none.
var site: Dictionary = {}
## The interpolator the picture was built from: own position and rotation, site period.
## A fresh one (identity rotation, no wrap) for pictures built by hand.
var interp: SnapshotInterpolator = SnapshotInterpolator.new()


static func build(ctx: StationContext) -> ContactPicture:
	var pic: ContactPicture = ContactPicture.new()
	pic.interp = ctx.interp
	var now: int = ctx.now_ms()
	var info: Dictionary = ctx.view.contacts.get("info", {})
	for id: int in ctx.interp.contact_ids():
		if id == ctx.crew.ship:
			continue
		var callsign: String = ctx.view.callsign(id)
		var letter: String = Palette.allegiance(callsign)
		# Own-faction ships carry their ship name, no prefix: friendly.
		if int(info.get(id, [0])[0]) & ContactsSection.FLAG_OWN:
			letter = "F"
		var pulse: float = ctx.crew.pulse("contact", id, now)
		pic._add("contact", id, callsign, letter, ctx.interp.contact_position(id), pulse)
	for m: Dictionary in ctx.crew.marks:
		var slot: int = m["slot"]
		var pulse: float = ctx.crew.pulse("mark", slot, now)
		pic._add("mark", slot, m["name"], "", ctx.mark_position(m), pulse)
	var own_site: int = ctx.site()
	var site_label: String = ctx.crew.site_name(own_site)
	if site_label != "":
		var site_pulse: float = ctx.crew.pulse("site", own_site, now)
		pic.site = {"kind": "site", "id": own_site, "label": site_label, "pulse": site_pulse}
	# Hazard zones and scan positions: MARK items outside the 8 marks (FT-SPA-028).
	for z: Dictionary in ctx.crew.zones:
		if z["site"] != own_site:
			continue
		var kind: String = z["kind"]
		var zone_label: String = String(TranslationServer.translate("zone." + kind))
		pic._add("zone", z["id"], zone_label, "", z["pos"], ctx.crew.pulse("zone", z["id"], now))
		pic.items[-1].merge({"zone": kind, "radius": z["radius"]})
	# The stations that silently copied a ping show on the original (FT-SPA-031).
	for it: Dictionary in pic.items:
		it["copies"] = ctx.crew.copies(it["kind"], it["id"], now)
	if not pic.site.is_empty():
		pic.site["copies"] = ctx.crew.copies("site", pic.site["id"], now)
	for p: Dictionary in ctx.crew.live_pings(now):
		if p["kind"] == "point":
			var pulse: float = 1.0 - float(now - int(p["at_ms"])) / float(CrewState.PING_MS)
			pic._add("point", -1, "", "", p["pos"], pulse)
	return pic


## The item with `ref`'s kind and id, or {}.
func find(ref: Dictionary) -> Dictionary:
	if ref.is_empty():
		return {}
	for it: Dictionary in items:
		if it["kind"] == ref.get("kind", "") and it["id"] == ref.get("id", -1):
			return it
	return {}


## Ship-frame offset (m) from the item `centre` ({} or gone: the own ship) of a point at
## `world` (world-axes offset from the own ship): the minimum image of the difference in
## world axes, then turned into the ship frame (D124).
func rel(world: Vector3, centre: Dictionary) -> Vector3:
	var c: Dictionary = find(centre)
	if c.is_empty():
		return interp.local(world)
	return interp.local(interp.min_image(world - (c["world"] as Vector3)))


func _add(kind: String, id: int, label: String, letter: String, pos: Vector3, pulse: float) -> void:
	var world: Vector3 = interp.offset_to(pos)
	(
		items
		. append(
			{
				"kind": kind,
				"id": id,
				"label": label,
				"allegiance": letter,
				"world": world,
				"local": interp.local(world),
				"pulse": pulse,
			}
		)
	)
