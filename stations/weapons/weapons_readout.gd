class_name WeaponsReadout
extends RefCounted
## Weapons' read-out texts (R13-7): the mount list (FT-WPN-004), the target line, the
## out-of-arc line (FT-WPN-005), the ammunition line (FT-WPN-006), other stations' feeds on the
## target (FT-WPN-007) and the contract flags (P9). Reads the panel; draws nothing. The touch
## controls' words are WeaponsStatus's.


## One line per mount (FT-WPN-004): number, id, state, heat, ammo, claimer; the camera
## mount marked.
static func mount_rows(p: WeaponsPanel) -> Array[String]:
	var out: Array[String] = []
	for i: int in p.mount_count():
		var m: MountDef = p.ship_def.mounts[i]
		var row: Dictionary = p.mount_row(i)
		var w: WeaponDef = p.weapon_of(i)
		var ammo: int = int(row.get("ammo", w.ammo_capacity))
		var ammo_text: String = "∞" if ammo < 0 else "%d/%d" % [ammo, w.ammo_capacity]
		var holder: Dictionary = p.holder(i)
		var who: String = p.tr("weapons.free")
		if p.is_mine(i):
			who = p.tr("weapons.you")
		elif not holder.is_empty():
			who = str(holder.get("name", ""))
		var heat: float = float(row.get("heat", 0.0)) / w.heat_limit
		(
			out
			. append(
				(
					"%s%d %s · %s · %s · %s · %s"
					% [
						"> " if i == p.mount else "  ",
						i + 1,
						m.id,
						p.tr("weapons." + mount_state(p, i)),
						p.tr("weapons.heat") % roundi(heat * 100.0),
						ammo_text,
						who,
					]
				)
			)
		)
	return out


## Mount i's state word key: no_data, empty, locked, hot, reloading or ready.
static func mount_state(p: WeaponsPanel, i: int) -> String:
	var row: Dictionary = p.mount_row(i)
	var w: WeaponDef = p.weapon_of(i)
	if row.is_empty():
		return "no_data"
	if int(row["ammo"]) == 0:
		return "empty"
	if bool(row.get("locked", false)):
		return "locked"
	if float(row["heat"]) >= w.heat_limit:
		return "hot"
	if float(row["cooldown"]) > 0.0:
		return "reloading"
	return "ready"


## The out-of-arc line (FT-WPN-005): "H2 out of arc: turn 4 high", the bow direction that
## brings the selected contact onto the mount's rest direction; "" when in arc or none.
static func out_of_arc_text(p: WeaponsPanel) -> String:
	var id: int = p.selected_contact()
	if p.mount_count() == 0 or id not in p.ctx.interp.contact_ids():
		return ""
	var m: MountDef = p.ship_def.mounts[p.mount]
	var local: Vector3 = (
		p.ctx.interp.local(p.ctx.interp.offset_to(p.ctx.interp.contact_position(id))) - m.position
	)
	if local.length_squared() < 1e-6 or m.forward.angle_to(local) <= m.arc_half_angle:
		return ""
	var swing: Vector3 = Quaternion(m.forward, local.normalized()) * Vector3.FORWARD
	return p.tr("weapons.out_of_arc").format(
		{"target": p.ctx.view.callsign(id), "dir": ChipText.clock_words(swing)}
	)


## The target line: "Target H2 · 4 high · mid", or "".
static func target_text(p: WeaponsPanel) -> String:
	var id: int = p.selected_contact()
	if id not in p.ctx.interp.contact_ids():
		return ""
	var local: Vector3 = p.ctx.interp.local(
		p.ctx.interp.offset_to(p.ctx.interp.contact_position(id))
	)
	return p.tr("weapons.target") % ChipText.chip(p.ctx.view.callsign(id), local)


## The camera mount's selected ammunition by name ("standard" for a mount with one).
static func ammo_name(p: WeaponsPanel) -> String:
	if p.mount_count() == 0 or p.ship_def.mounts[p.mount].alt_weapons.is_empty():
		return p.tr("weapons.ammo_standard")
	return p.weapon_of(p.mount).display_name


## The ammunition line (FT-WPN-006): the selected type, "standard" for a mount with one.
static func ammo_text(p: WeaponsPanel) -> String:
	if p.mount_count() == 0 or p.ship_def.mounts[p.mount].alt_weapons.is_empty():
		return p.tr("weapons.ammo") % p.tr("weapons.ammo_standard")
	return p.tr("weapons.ammo") % p.weapon_of(p.mount).display_name


## What other stations' work says of the selected target (FT-WPN-007, P7, P8): its
## weak points by name, how the selected ammunition fares against its resistances, the open
## hack window and the track quality. Each line exists only while the server sends its feed,
## that is while its toggle is on or Science and Relay share this view.
static func feed_lines(p: WeaponsPanel) -> Array[String]:
	var out: Array[String] = []
	var id: int = p.selected_contact()
	var feeds: Dictionary = p.ctx.view.blocks.get(StationViews.Section.FEEDS, {})
	if id < 0 or feeds.is_empty():
		return out
	var flag: int = contract_flag(p, id)
	if flag != 0:
		out.append(p.tr("weapons.flag_line_%d" % flag))
	for row: Dictionary in feeds["weak"]:
		if row["contact"] != id:
			continue
		var def: ShipDef = ScienceLookup.ship_class(row["class_id"])
		var names: PackedStringArray = PackedStringArray()
		for i: int in 32:
			if (int(row["weak_mask"]) >> i) & 1 == 1 and def != null and i < def.subsystems.size():
				names.append(String(def.subsystems[i].id))
		if not names.is_empty():
			out.append(p.tr("weapons.weak") % ", ".join(names))
		if p.mount_count() > 0:
			var kind: StringName = p.weapon_of(p.mount).damage_type
			for r: Dictionary in row["resist"]:
				if r["type"] == BlockSchema.id_code(kind):
					out.append(p.tr("weapons.rating") % [String(kind), float(r["factor"])])
	for w: Dictionary in feeds["windows"]:
		if w["target"] == id:
			out.append(p.tr("weapons.window") % ceili(float(w["left"])))
	for t: Dictionary in feeds["tracks"]:
		if t["contact"] == id:
			var q: float = clampf(float(t["quality"]), 0.0, 1.0)
			var bar: String = "#".repeat(roundi(q * 8.0)) + "-".repeat(8 - roundi(q * 8.0))
			out.append(p.tr("weapons.track") % [roundi(q * 100.0), bar])
	return out


## The contract flag a contact carries (P9, FT-MIS-042): 1 disable ("do not destroy"), 2
## protect, 0 none. The FEEDS block holds the rows only while the contract flags are shared
## with this view (the P9 toggle, or Comms on this screen).
static func contract_flag(p: WeaponsPanel, contact: int) -> int:
	var feeds: Dictionary = p.ctx.view.blocks.get(StationViews.Section.FEEDS, {})
	for row: Dictionary in feeds.get("flags", []):
		if int(row["contact"]) == contact:
			return int(row["flag"])
	return 0


## The chip text of an item: "H2 4 high 2.3km", and a contact a contract flags names its
## flag ("[disable]", "[protect]", P9).
static func target_chip(p: WeaponsPanel, it: Dictionary) -> String:
	var chip: String = ContactPicture.chip_of(it)
	var flag: int = contract_flag(p, int(it["id"])) if it["kind"] == "contact" else 0
	if flag != 0:
		chip += " [%s]" % p.tr("weapons.flag_%d" % flag)
	return chip


## The claim hint under the read-outs while this client doesn't hold the camera mount: how
## to claim it when free, who holds it when not; "" when it is ours.
static func hint(p: WeaponsPanel) -> String:
	var holder: Dictionary = p.holder(p.mount)
	if p.is_mine(p.mount):
		return ""
	if holder.is_empty():
		if p.tablet() != null:
			# Touch rails: the Claim button, not a key.
			return p.tr("weapons.hint_claim_touch")
		var keys: PackedStringArray = p.ctx.settings.bindings.bindings(
			"claim", p.ctx.matcher.device
		)
		return p.tr("weapons.hint_claim") % BindingText.describe_all(keys)
	return p.tr("weapons.held_by") % str(holder.get("name", ""))
