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
## The nearest named site's name as a callout layer on every station (FT-SPA-027, D98,
## D229): {"kind": "site", "id", "label", "pulse"}, or {} when the faction knows no site.
var site: Dictionary = {}
## Every named site the faction knows as an item ({"kind": "site", "id", "label",
## "allegiance" "", "world", "local", "pulse"} plus "radius" and "dockable"): selectable
## like contacts (FT-SPA-015) but kept out of `items`, which the radars draw.
var sites: Array[Dictionary] = []
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
	pic._add_sites(ctx, now)
	# Hazard zones and scan positions: MARK items outside the 8 marks (FT-SPA-028).
	for z: Dictionary in ctx.crew.zones:
		var kind: String = z["kind"]
		var zone_label: String = String(TranslationServer.translate("zone." + kind))
		pic._add("zone", z["id"], zone_label, "", z["pos"], ctx.crew.pulse("zone", z["id"], now))
		pic.items[-1].merge({"zone": kind, "radius": z["radius"]})
	# The sim's hazards the faction knows (D208): zones and shells as hazard bubbles, a plane
	# front as a line across its travel (`dir`, ship frame).
	var hazard_label: String = String(TranslationServer.translate("zone.hazard"))
	for h: Dictionary in ctx.view.blocks.get(StationViews.Section.RELAY, {}).get("hazards", []):
		pic._add("zone", -1000 - int(h["id"]), hazard_label, "", h["pos"], 0.0)
		pic.items[-1].merge({"zone": "hazard", "radius": h["radius"], "eta": h["eta"]})
		if int(h["shape"]) == HazardView.PLANE:
			pic.items[-1]["dir"] = pic.interp.local(h["dir"])
	# Deployed probes with their bubbles (P13): Science and Relay see where coverage is.
	var probe_label: String = String(TranslationServer.translate("zone.probe"))
	for p: Dictionary in ctx.view.blocks.get(StationViews.Section.RELAY, {}).get("probes", []):
		if p["deployed"]:
			var id: int = int(p["serial"])
			pic._add("zone", -1 - id, probe_label, "", p["pos"], 0.0)
			pic.items[-1].merge({"zone": "probe", "radius": p["range"]})
	# The stations that silently copied a ping show on the original (FT-SPA-031).
	for it: Dictionary in pic.items:
		it["copies"] = ctx.crew.copies(it["kind"], it["id"], now)
	for it: Dictionary in pic.sites:
		it["copies"] = ctx.crew.copies("site", it["id"], now)
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
	for it: Dictionary in sites:
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


## Fills `sites` from the SITES section and `site` with the one nearest the own ship.
func _add_sites(ctx: StationContext, now: int) -> void:
	var nearest: float = INF
	for row: Dictionary in ctx.view.sites:
		var id: int = row["id"]
		var label: String = String(TranslationServer.translate(StringName(row["name_key"])))
		var world: Vector3 = interp.offset_to(row["pos"])
		var pulse: float = ctx.crew.pulse("site", id, now)
		(
			sites
			. append(
				{
					"kind": "site",
					"id": id,
					"label": label,
					"allegiance": "",
					"world": world,
					"local": interp.local(world),
					"pulse": pulse,
					"radius": row["radius"],
					"dockable": row["dockable"],
				}
			)
		)
		if world.length() < nearest:
			nearest = world.length()
			site = {"kind": "site", "id": id, "label": label, "pulse": pulse}


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
