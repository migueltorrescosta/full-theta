class_name ChipSource
extends RefCounted
## The Captain's read-only list of open request chips (FT-CPT-004). Strand G owns chips
## and Section.CHIPS; this is the one place the Captain panel asks for them:
## `open_chips(ctx)` returns the rows of the CHIPS block when the snapshot has one (G
## maps its fields in `from_block`), else a fixture list so the panel is complete before
## chips exist (D190's rule for Comms' cards, applied here).
##
## A row: {"from": station id, "to": station id, "label": text, "left_s": seconds left}.


## The chips open on the ship now.
static func open_chips(ctx: StationContext) -> Array[Dictionary]:
	if ctx.view.blocks.has(StationViews.Section.CHIPS):
		return from_block(ctx.view.blocks[StationViews.Section.CHIPS])
	return fixture()


## Rows of the CHIPS block (strand G fills this in with the block's fields).
static func from_block(_block: Dictionary) -> Array[Dictionary]:
	return []


## The fixture: a boost request from Helm to Engineering with 6 s left (§5.7 wireframe).
static func fixture() -> Array[Dictionary]:
	return [
		{
			"from": "helm",
			"to": "engineering",
			"label": TranslationServer.translate("captain.fixture_chip"),
			"left_s": 6.0,
		}
	]
