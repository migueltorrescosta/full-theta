class_name SitesSection
extends SnapshotSection
## Section.SITES: the named sites one faction knows (D229, FT-SPA-015, FT-SPA-027), shared by
## every view of its ships (owner = faction, like CONTACTS). Sent whole, and only when the
## list changed (a site opening or being revealed), so it costs nothing in a quiet tick
## (D225). At most MAX_ROWS rows. Replaces the one-shot "sites" event.
##
## Wire: u8 n, then per row u16 site id, u8 kind (index in SiteDef.KINDS), u8 dockable,
## u8 pending, f32 radius (m), the point as 3 x s32 (1/16 m, NetCodec.quant_pos) and u8
## length + UTF-8 name key. Sites don't move, so the client keeps them as they come.
## `pending` is 1 while an encounter of the faction waits at the site and opened at least
## RunDef.site_marker_delay ago (never without a RunDef): Relay's map marks it "?" (gp-16,
## amends D250). It flips twice per encounter, so the section is resent then.

## Most rows the section carries (D225: at most 32 rows).
const MAX_ROWS: int = 32


func _init(faction: int) -> void:
	super(StationCatalogue.Section.SITES, faction)


func update(world: SimWorld) -> PackedByteArray:
	var sites: SiteTable = world.sites
	var p_units: int = NetCodec.period_units(world.kin.period)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(0)
	var n: int = 0
	var pending: Dictionary[int, bool] = pending_sites(world, owner)
	for id: int in sites.size():
		if not sites.is_known(id, owner) or n >= MAX_ROWS:
			continue
		var name: PackedByteArray = sites.name_keys[id].to_utf8_buffer().slice(0, 255)
		buf.put_u16(id)
		buf.put_u8(sites.kind_ix[id])
		buf.put_u8(sites.dockable[id])
		buf.put_u8(1 if pending.has(id) else 0)
		buf.put_float(sites.radius[id])
		NetCodec.put3_32(buf, NetCodec.quant_pos(sites.point(id), p_units))
		buf.put_u8(name.size())
		buf.put_data(name)
		n += 1
	buf.seek(0)
	buf.put_u8(n)
	var bytes: PackedByteArray = buf.data_array
	return _changed(bytes)


## The sites of the faction's PENDING encounters opened at least site_marker_delay ago.
static func pending_sites(world: SimWorld, faction: int) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	if world.run_def == null:
		return out
	var t: EncounterTable = world.encounters
	var delay: int = SimRate.ticks(world.run_def.site_marker_delay)
	for e: int in t.size():
		if (
			t.result[e] == EncounterTable.Result.PENDING
			and t.site[e] >= 0
			and t.owner_faction[e] == faction
			and world.tick >= t.open_tick[e] + delay
		):
			out[t.site[e]] = true
	return out
