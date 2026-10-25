class_name FeedsView
extends RefCounted
## Section.FEEDS: what Weapons gets from other stations' work (P7 weak points and ammunition
## ratings, hack windows; P8 track feeds with a quality bar), built from KNOW and the hack
## table when ViewFilter.grants() lets the view have it (FT-PAIR-007, FT-WPN-007). The
## weak points and resistances are the faction's scan knowledge (ScienceKnowledge): what
## Science revealed, no more. Tracks are the contacts the faction detects, with the
## detection confidence as quality (the bar) and whether a deployed probe covers them.

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
						"quality": ScienceKnowledge.detection_confidence(world, faction, contact),
						"probe": ProbeSystem.covers_contact(world, ship, contact),
					}
				)
			)
		if (out["weak"] as Array).size() >= MAX_ROWS:
			continue
		var card: Dictionary = _weak_row(world, faction, contact)
		if not card.is_empty():
			(out["weak"] as Array).append(card)
	var h: HackTable = world.hacks
	for r: int in h.size():
		if h.factions[r] == faction and (out["windows"] as Array).size() < MAX_ROWS:
			(
				(out["windows"] as Array)
				. append(
					{
						"target": h.ship_ids[r],
						"sub": h.subsystem[r],
						"left": maxf(0.0, (h.until_tick[r] - world.tick) * SimWorld.DT),
						"by": h.by[r],
					}
				)
			)
	return out


## The contact's revealed weak points and resistances, or {} when the scan revealed neither.
static func _weak_row(world: SimWorld, faction: int, contact: int) -> Dictionary:
	if world.science_def == null:
		return {}
	var mask: int = 0
	for i: int in ScienceKnowledge.weak_points(world, faction, contact):
		mask |= 1 << i
	var resist: Array = []
	var factors: Dictionary[StringName, float] = ScienceKnowledge.resistances(
		world, faction, contact
	)
	for type: StringName in factors:
		resist.append({"type": ScienceView.code(type), "factor": factors[type]})
	if mask == 0 and resist.is_empty():
		return {}
	return {"contact": contact, "weak_mask": mask, "resist": resist}
