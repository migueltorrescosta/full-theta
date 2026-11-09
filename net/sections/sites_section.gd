class_name SitesSection
extends SnapshotSection
## Section.SITES: the named sites one faction knows (D229, FT-SPA-015, FT-SPA-027), shared by
## every view of its ships (owner = faction, like CONTACTS). Sent whole, and only when the
## list changed (a site opening or being revealed), so it costs nothing in a quiet tick
## (D225). At most MAX_ROWS rows. Replaces the one-shot "sites" event.
##
## Wire: u8 n, then per row u16 site id, u8 kind (index in SiteDef.KINDS), u8 dockable,
## f32 radius (m), the point as 3 x s32 (1/16 m, NetCodec.quant_pos) and u8 length + UTF-8
## name key. Sites don't move, so the client keeps them as they come.

## Most rows the section carries (D225: at most 32 rows).
const MAX_ROWS: int = 32


func _init(faction: int) -> void:
	super(StationViews.Section.SITES, faction)


func update(world: SimWorld) -> PackedByteArray:
	var sites: SiteTable = world.sites
	var p_units: int = NetCodec.period_units(world.kin.period)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(0)
	var n: int = 0
	for id: int in sites.size():
		if not sites.is_known(id, owner) or n >= MAX_ROWS:
			continue
		var name: PackedByteArray = sites.name_keys[id].to_utf8_buffer().slice(0, 255)
		buf.put_u16(id)
		buf.put_u8(sites.kind_ix[id])
		buf.put_u8(sites.dockable[id])
		buf.put_float(sites.radius[id])
		NetCodec.put3_32(
			buf, NetCodec.quant_pos(sites.pos_x[id], sites.pos_y[id], sites.pos_z[id], p_units)
		)
		buf.put_u8(name.size())
		buf.put_data(name)
		n += 1
	buf.seek(0)
	buf.put_u8(n)
	var bytes: PackedByteArray = buf.data_array
	return _changed(bytes)
