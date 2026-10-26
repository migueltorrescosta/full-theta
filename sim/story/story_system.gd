class_name StorySystem
extends RefCounted
## Lets cards lapse (FT-COM-008): an OPEN or ACCEPTED card past its expiry turns EXPIRED
## and closes its conversation. Everything else in STORY happens in commands.


static func step(world: SimWorld) -> void:
	var t: StoryTable = world.story
	for card: int in t.size():
		var due: int = t.expires_tick[card]
		if due >= 0 and world.tick >= due and Story.is_live(world, card):
			Story.set_state(world, Story.audience_ship(world, card), card, StoryTable.State.EXPIRED)
	StoryRules.step(world)  # --- strand F ---
