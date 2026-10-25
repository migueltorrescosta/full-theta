extends GdUnitTestSuite
## The load probe's snapshot rows (D161): one value per field, the part times one per
## StationViews.Section kind after the near sets, so tools/l4/load_check.py reads the
## capture stamp from the right column.


# FT: FT-NET-040, FT-TST-011
# A section added without a field name shifts every later column of every row, and the
# snapshot age then reads a section time as the capture stamp.
func test_snap_fields_cover_every_section() -> void:
	var fixed: int = NetTransport.SNAP_FIELDS.find("near_sets_us")
	assert_int(fixed).is_greater(0)
	assert_int(NetTransport.SNAP_FIELDS.size()).is_equal(fixed + 1 + StationViews.Section.size())
	for kind: String in StationViews.Section.keys():
		assert_bool(NetTransport.SNAP_FIELDS.has(kind.to_lower() + "_us")).is_true()
