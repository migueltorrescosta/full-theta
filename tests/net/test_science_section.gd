extends GdUnitTestSuite
## The SCIENCE card's revealed-parts mask (12r-23, FT-SCI-002): the server sets bit i for
## BlockSchema.SCIENCE_REVEALED[i] from ScienceKnowledge (cargo included, own ships always),
## and it survives the wire. ScienceSection.block_bytes gives the bytes of the encoded
## block whichever way the faction's rows are shared (w-j12).


func _card(w: SimWorld, contact: int) -> Dictionary:
	for card: Dictionary in ScienceSection.block(w, ScienceFixture.ME)["cards"]:
		if card["contact"] == contact:
			return card
	return {}


# FT: FT-SCI-002
func test_bit_order_is_pinned_to_the_parts() -> void:
	(
		assert_array(BlockSchema.SCIENCE_REVEALED)
		. is_equal(
			[
				ScienceKnowledge.CLASS,
				ScienceKnowledge.IDENTITY,
				ScienceKnowledge.INTENT,
				ScienceKnowledge.WEAK_POINTS,
				ScienceKnowledge.RESISTANCES,
				ScienceKnowledge.HACK,
				ScienceKnowledge.CARGO,
			]
		)
	)


# FT: FT-SCI-002
func test_mask_follows_each_threshold() -> void:
	var w: SimWorld = ScienceFixture.world()
	var def: ScienceDef = w.science_def
	var row: int = w.knowledge.row_for(ScienceFixture.BLUE, ScienceFixture.FOE)
	assert_int(ScienceSection.revealed_mask(w, ScienceFixture.BLUE, ScienceFixture.FOE)).is_equal(0)
	for i: int in BlockSchema.SCIENCE_REVEALED.size():
		var part: StringName = BlockSchema.SCIENCE_REVEALED[i]
		var need: float = ScienceKnowledge.threshold(def, part)
		assert_float(need).is_less_equal(1.0)
		w.knowledge.scan_conf[row] = need
		(
			assert_int(
				(ScienceSection.revealed_mask(w, ScienceFixture.BLUE, ScienceFixture.FOE) >> i) & 1
			)
			. is_equal(1)
		)
		w.knowledge.scan_conf[row] = need - 0.01
		(
			assert_int(
				(ScienceSection.revealed_mask(w, ScienceFixture.BLUE, ScienceFixture.FOE) >> i) & 1
			)
			. is_equal(0)
		)
	w.knowledge.scan_conf[row] = 1.0
	assert_int(ScienceSection.revealed_mask(w, ScienceFixture.BLUE, ScienceFixture.FOE)).is_equal(
		0x7F
	)


# FT: FT-SCI-002
func test_own_ships_are_always_revealed() -> void:
	var w: SimWorld = ScienceFixture.world()
	assert_int(ScienceSection.revealed_mask(w, ScienceFixture.BLUE, ScienceFixture.ME)).is_equal(
		0x7F
	)
	assert_int(ScienceSection.revealed_mask(w, ScienceFixture.RED, ScienceFixture.FOE)).is_equal(
		0x7F
	)


# FT: FT-SCI-002
func test_mask_round_trips_on_the_wire() -> void:
	var w: SimWorld = ScienceFixture.world()
	var row: int = w.knowledge.row_for(ScienceFixture.BLUE, ScienceFixture.FOE)
	w.knowledge.scan_conf[row] = w.science_def.reveal_cargo
	var block: Dictionary = ScienceSection.block(w, ScienceFixture.ME)
	var want: int = _card(w, ScienceFixture.FOE)["revealed"]
	assert_int(want).is_not_equal(0)
	var schema: Array = BlockSchema.BLOCKS[StationCatalogue.Section.SCIENCE]
	var back: Dictionary = NetBlock.decode(schema, NetBlock.encode(schema, block))
	var got: Dictionary = {}
	for card: Dictionary in back["cards"]:
		if card["contact"] == ScienceFixture.FOE:
			got = card
	assert_int(got["revealed"]).is_equal(want)
	assert_bool(ScienceCard.is_revealed(got, ScienceKnowledge.CARGO)).is_true()
	assert_bool(ScienceCard.is_revealed(got, ScienceKnowledge.RESISTANCES)).is_false()


## What a client must get: the encoded block, built for this ship alone.
func _encoded(w: SimWorld, ship: int) -> PackedByteArray:
	return NetBlock.encode(
		BlockSchema.BLOCKS[StationCatalogue.Section.SCIENCE], ScienceSection.block(w, ship)
	)


# FT: FT-SCI-001, FT-SCI-002
func test_block_bytes_are_the_encoded_block() -> void:
	var w: SimWorld = ScienceFixture.world()
	ScienceFixture.do(w, ScienceFixture.scan_cmd())
	w.knowledge.scan_conf[w.knowledge.row_for(ScienceFixture.BLUE, ScienceFixture.FOE)] = 1.0
	assert_int(w.science.kind[ScienceFixture.ME]).is_equal(ScienceTable.Minigame.SCAN)
	assert_array(ScienceSection.block(w, ScienceFixture.ME)["cards"]).is_not_empty()
	for ship: int in [ScienceFixture.ME, ScienceFixture.FOE]:
		assert_array(ScienceSection.block_bytes(w, ship)).is_equal(_encoded(w, ship))
	w.science_def = null
	assert_array(ScienceSection.block_bytes(w, ScienceFixture.ME)).is_equal(
		_encoded(w, ScienceFixture.ME)
	)


# FT: FT-NET-040, FT-SCI-002
# A build encodes a faction's rows once for all its ships, and the next build encodes
# them again from the world it is given.
func test_writer_shares_a_factions_rows_within_one_build() -> void:
	var w: SimWorld = ScienceFixture.world()
	var wing: int = ScienceFixture.wing(w)
	var ships: Array[int] = [ScienceFixture.ME, wing, ScienceFixture.FOE]
	var keys: Array = ships.map(func(s: int) -> String: return StationCatalogue.key(s, "science"))
	var row: int = w.knowledge.row_for(ScienceFixture.BLUE, ScienceFixture.FOE)
	var b: SnapshotWriter = SnapshotWriter.new()
	for conf: float in [0.0, 0.5, 1.0]:
		w.knowledge.scan_conf[row] = conf
		b.build(w, 1, keys)
		for ship: int in ships:
			var section: SnapshotSection = b.section(StationCatalogue.Section.SCIENCE, ship)
			assert_array(section.full()).is_equal(_encoded(w, ship))
	var cards: Array = ScienceSection.block(w, wing)["cards"]
	assert_array(cards).is_equal(ScienceSection.block(w, ScienceFixture.ME)["cards"])
	assert_array(cards).is_not_empty()


# FT: FT-SCI-002
# A block section updated outside a writer keeps no rows from one update to the next.
func test_block_section_rebuilds_the_rows_each_update() -> void:
	var w: SimWorld = ScienceFixture.world()
	var section: BlockSection = BlockSection.new(
		StationCatalogue.Section.SCIENCE, ScienceFixture.ME
	)
	section.update(w)
	w.knowledge.scan_conf[w.knowledge.row_for(ScienceFixture.BLUE, ScienceFixture.FOE)] = 1.0
	assert_array(section.update(w)).is_equal(_encoded(w, ScienceFixture.ME))
