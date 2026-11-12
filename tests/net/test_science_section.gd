extends GdUnitTestSuite
## The SCIENCE card's revealed-parts mask (12r-23, FT-SCI-002): the server sets bit i for
## BlockSchema.SCIENCE_REVEALED[i] from ScienceKnowledge (cargo included, own ships always),
## and it survives the wire.


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
