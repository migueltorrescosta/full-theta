class_name FeedsView
extends RefCounted
## Section.FEEDS: what Weapons gets from other stations' work (P7 weak points and ammunition
## ratings, hack windows; P8 track feeds with a quality bar), built from KNOW and the hack
## table when ViewFilter.grants() lets the view have it (FT-PAIR-007, FT-WPN-007). The
## weak points and resistances are the faction's scan knowledge (ScienceKnowledge): what
## Science revealed, no more. Tracks are the contacts the faction detects, with the track
## quality (GuidanceSystem.track_quality, D214: the bar) and whether a deployed probe covers
## them.

## Rows a list may hold (a row count is one byte).
const MAX_ROWS: int = 255


## The FEEDS block of a ship with everything granted (ViewFilter.apply() empties the lists
## the view may not have).
static func block(world: SimWorld, ship: int) -> Dictionary:
	var faction: int = world.faction_of(ship)
	var out: Dictionary = {"weak": [], "windows": [], "tracks": []}
	var k: KnowledgeTable = world.knowledge
	for r: int in k.size():
		if k.factions[r] != faction:
			continue
		var contact: int = k.ship_ids[r]
		if k.detected[r] == 1 and (out["tracks"] as Array).size() < MAX_ROWS:
			(
				(out["tracks"] as Array)
				. append(
					{
						"contact": contact,
						"quality": GuidanceSystem.track_quality(world, faction, contact),
						"probe": ProbeSystem.covers_contact(world, ship, contact),
					}
				)
			)
		if (out["weak"] as Array).size() >= MAX_ROWS:
			continue
		var card: Dictionary = _weak_row(world, faction, contact)
		if not card.is_empty():
			(out["weak"] as Array).append(card)
	out["windows"] = ScienceView.hacks(world, faction)
	return out


## The contact's revealed weak points and resistances, or {} when the scan revealed neither.
static func _weak_row(world: SimWorld, faction: int, contact: int) -> Dictionary:
	if world.science_def == null:
		return {}
	var traits: Dictionary = ScienceView.revealed_traits(world, faction, contact)
	if traits["weak_mask"] == 0 and (traits["resist"] as Array).is_empty():
		return {}
	# The weak points name subsystems of the contact's class: that is known once they are.
	var class_id: int = ScienceView.code(world.defs[contact].id)
	return {
		"contact": contact,
		"class_id": class_id,
		"weak_mask": traits["weak_mask"],
		"resist": traits["resist"]
	}
