class_name ChipSource
extends RefCounted
## The Captain's read-only list of open request chips (FT-CPT-004). Strand G owns chips
## and Section.CHIPS; this is the one place the Captain panel asks for them:
## `open_chips(ctx)` returns the rows of the CHIPS block when the snapshot has one
## (`from_block`, over ChipView), else a fixture list so the panel is complete before
## chips exist (D190's rule for Comms' cards, applied here).
##
## A row: {"from": station id, "to": station id, "label": text, "left_s": seconds left}.


## The chips open on the ship now.
static func open_chips(ctx: StationContext) -> Array[Dictionary]:
	if ctx.view.blocks.has(StationViews.Section.CHIPS):
		return from_block(ctx.view)
	return fixture()


## Rows of the view's CHIPS block, all of the ship's open chips (the Captain sees them
## all), with the text in the session language and the seconds left.
static func from_block(view: NetViewState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for chip: Dictionary in ChipView.open_chips(view):
		var callsign: String = view.callsign(int(chip["arg"])) if int(chip["arg"]) >= 0 else ""
		(
			rows
			. append(
				{
					"from": chip["from"],
					"to": chip["to"],
					"label": ChipView.label(chip, callsign),
					"left_s": ChipView.left_s(view, chip),
				}
			)
		)
	return rows


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
