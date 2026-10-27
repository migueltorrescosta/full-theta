class_name StoryRules
extends RefCounted
## The cooperation rules of Comms with other stations (#10): what STORY does
## when the rest of the crew acts. The flags are Story's named integers (StoryFlagTable),
## so these rules add no column to a table. All of them apply at every difficulty
## (FT-PAIR-014); the toggles only decide what a screen shows.
## - P5 approach lanes (FT-PAIR-001): a clearance card carries a window; docking at its
##   site inside the window is cleared, docking without one loses reputation.
## - P9 surrender (FT-MIS-042): a conversation roll whose chance rises with the contact's
##   engine damage, and a reputation loss for destroying a surrendered contact.
## - P12 terms: an offer can need power on a subsystem, which the ship may not have.
## - P14 scan facts: a scan that reaches a fact's confidence teaches the faction the fact.
## - P15 locating: Relay marks a mission, and a probe that finds a contact that can be
##   hailed opens an opportunity on Comms' board.

## Reputation draws (content/economy/rep/).
const UNCLEARED: StringName = &"rep.uncleared_approach"
const SURRENDER_KILL: StringName = &"rep.destroy_surrendered"

const _LANE_OPEN: String = "lane.open.%d"
const _LANE_LEN: String = "lane.len.%d"
const _LANE_T0: String = "lane.t0.%d"
const _NEED: String = "need.%d."
const _DOCKED: String = "docked.%d"
const _OPPORTUNITY: String = "opp.%d.%d"
const _MARKED: String = "marked.%d"

# --- P5: approach lanes ---


## Makes the card a clearance: after it is accepted, the lane opens `open_s` later and
## stays open `length_s`.
static func set_lane(world: SimWorld, card: int, open_s: float, length_s: float) -> void:
	if not length_s > 0.0:
		return
	var f: StoryFlagTable = world.story_flags
	f.set_flag(StringName(_LANE_OPEN % card), maxi(0, ceili(open_s * SimWorld.HZ)))
	f.set_flag(StringName(_LANE_LEN % card), ceili(length_s * SimWorld.HZ))


static func is_lane(world: SimWorld, card: int) -> bool:
	return world.story_flags.get_flag(StringName(_LANE_LEN % card)) > 0


## The accepted clearance's window as [first tick, last tick], or [] while the card isn't
## an accepted clearance.
static func lane_window(world: SimWorld, card: int) -> Array[int]:
	var out: Array[int] = []
	var t0: int = world.story_flags.get_flag(StringName(_LANE_T0 % card))
	if t0 > 0 and is_lane(world, card):
		var first: int = t0 - 1 + world.story_flags.get_flag(StringName(_LANE_OPEN % card))
		out.assign([first, first + world.story_flags.get_flag(StringName(_LANE_LEN % card))])
	return out


## Called when a card is accepted: a clearance starts its clock.
static func on_accept(world: SimWorld, card: int) -> void:
	if is_lane(world, card):
		world.story_flags.set_flag(StringName(_LANE_T0 % card), world.tick + 1)


## The ship's clearance card for the site: the newest, or -1.
static func clearance_for(world: SimWorld, ship: int, site: int) -> int:
	for card: int in range(world.story.size() - 1, -1, -1):
		if (
			world.story.site[card] == site
			and is_lane(world, card)
			and Story.visible_to(world, card, ship)
		):
			return card
	return -1


## A ship that docked at a site with a clearance card (DockCommand, read through
## Story.docked_site). Inside the window the card is done and
## pays its reward; otherwise the standing with the site's faction falls by the
## rep.uncleared_approach draw and the card fails. Emits dock_cleared or dock_uncleared.
static func on_dock(world: SimWorld, ship: int, site: int) -> void:
	var card: int = clearance_for(world, ship, site)
	if card < 0 or not Story.is_live(world, card):
		return
	var window: Array[int] = lane_window(world, card)
	var cleared: bool = (
		world.story.state[card] == StoryTable.State.ACCEPTED
		and not window.is_empty()
		and world.tick >= window[0]
		and world.tick <= window[1]
	)
	if cleared:
		Story.set_state(world, ship, card, StoryTable.State.DONE)
		Economy.add_credits(world, ship, world.story.reward[card])
		world.emit(&"dock_cleared", ship, card)
		return
	Story.set_state(world, ship, card, StoryTable.State.FAILED)
	var delta: float = 0.0
	if world.story.rep_faction[card] >= 0:
		delta = Reputation.change(
			world, ship, world.story.factions[card], world.story.rep_faction[card], UNCLEARED
		)
	world.emit(&"dock_uncleared", ship, card, delta)


# --- settling a card ---


## Settles an accepted card: success pays the reward and draws the card's reputation
## change; failure draws "<interaction>.fail" if there is one (FT-COM-005, FT-MIS-021).
static func settle(world: SimWorld, ship: int, card: int, success: bool) -> void:
	var t: StoryTable = world.story
	Story.set_state(
		world, ship, card, StoryTable.State.DONE if success else StoryTable.State.FAILED
	)
	var dist: StringName = t.rep_interaction[card]
	if success:
		Economy.add_credits(world, ship, t.reward[card])
	elif dist != &"":
		dist = StringName(String(dist) + ".fail")
	if dist != &"" and t.rep_faction[card] >= 0:
		Reputation.change(world, ship, t.factions[card], t.rep_faction[card], dist)


# --- P9: surrender ---


## The chance that a contact surrenders when asked: `base` plus `per_damage` times the
## share of its engines' effectiveness that is gone, at most `cap` (all dimensionless).
## Prior engine damage raises it (FT-PAIR-004 P9).
static func surrender_chance(world: SimWorld, contact: int, params: Dictionary) -> float:
	var damage: float = 1.0 - DamageSystem.effectiveness(world, contact, &"engines")
	var chance: float = (
		float(params.get("base", 0.0)) + float(params.get("per_damage", 0.0)) * damage
	)
	return clampf(chance, 0.0, float(params.get("cap", 1.0)))


## A reply asked the card's contact to surrender: draws from the "surrender" stream and
## sets the faction's intent for the contact to SURRENDERING, or HOSTILE when it refuses.
## Emits surrender_roll (value the chance, tag &"yes" or &"no").
static func roll_surrender(world: SimWorld, ship: int, card: int, params: Dictionary) -> void:
	var t: StoryTable = world.story
	var chance: float = surrender_chance(world, t.target[card], params)
	var yes: bool = world.rng.stream(&"surrender").randf() < chance
	var row: int = world.knowledge.ensure_contact(t.factions[card], t.target[card])
	world.knowledge.intent[row] = (
		KnowledgeTable.Intent.SURRENDERING if yes else KnowledgeTable.Intent.HOSTILE
	)
	world.emit(
		&"surrender_roll", ship, t.target[card], chance, Vector3.ZERO, &"yes" if yes else &"no"
	)


## A ship was destroyed by `source`: if the source's faction had the victim as surrendering,
## the source loses reputation with the victim's faction (rep.destroy_surrendered) and the
## debrief gets a line (event surrender_killed, tag debrief.surrender_killed, value the
## change). An accepted "disable, do not destroy" contract on the victim fails.
static func on_destroyed(world: SimWorld, victim: int, source: int) -> void:
	if source >= 0 and source < world.ship_count():
		var fs: int = world.faction_of(source)
		var row: int = world.knowledge.row_for(fs, victim)
		if row >= 0 and world.knowledge.intent[row] == KnowledgeTable.Intent.SURRENDERING:
			var delta: float = Reputation.change(
				world, source, fs, world.faction_of(victim), SURRENDER_KILL
			)
			world.emit(
				&"surrender_killed",
				source,
				victim,
				delta,
				Vector3.ZERO,
				&"debrief.surrender_killed"
			)
	var t: StoryTable = world.story
	for card: int in t.size():
		if (
			t.target[card] == victim
			and t.target_flag[card] == KnowledgeTable.Flag.DISABLE
			and t.state[card] == StoryTable.State.ACCEPTED
		):
			settle(world, Story.audience_ship(world, card), card, false)


# --- P12: terms the ship may not meet ---


## Makes the offer need `pips` of power on the subsystem (the card's terms; Comms sees them,
## not the ship's condition).
static func set_need(world: SimWorld, card: int, subsystem: StringName, pips: int) -> void:
	if subsystem != &"" and pips > 0:
		world.story_flags.set_flag(StringName((_NEED % card) + String(subsystem)), pips)


## The card's need as {subsystem, pips}, or {}.
static func need_of(world: SimWorld, card: int) -> Dictionary:
	var prefix: String = _NEED % card
	var f: StoryFlagTable = world.story_flags
	for i: int in f.names.size():
		if String(f.names[i]).begins_with(prefix):
			return {
				"subsystem": StringName(String(f.names[i]).trim_prefix(prefix)), "pips": f.values[i]
			}
	return {}


## Whether the ship can meet the card's need now: the subsystem's effectiveness times the
## pips one subsystem can hold is at least the pips asked (true for a card with no need).
static func needs_met(world: SimWorld, ship: int, card: int) -> bool:
	var need: Dictionary = need_of(world, card)
	if need.is_empty():
		return true
	var usable: float = (
		DamageSystem.effectiveness(world, ship, need["subsystem"])
		* world.defs[ship].power.max_pips_per_subsystem
	)
	return usable >= int(need["pips"])


# --- P14: scan facts ---


## The scan facts of a contact the faction's best scan confidence `conf` has reached, as
## ScienceDef gives them: each is learned once (Story.learn_fact).
static func learn_scan_facts(world: SimWorld, faction: int, contact: int, conf: float) -> void:
	if world.science_def != null and conf >= world.science_def.reveal_cargo:
		Story.learn_fact(world, faction, contact, "cargo")


# --- P15: locating missions and opportunities ---


## Relay marked the mission's place: Comms' card shows the mark icon under mission_icon.
static func mark_mission(world: SimWorld, ship: int, card: int) -> bool:
	if not Story.visible_to(world, card, ship) or not Story.is_live(world, card):
		return false
	world.story_flags.set_flag(StringName(_MARKED % card), 1)
	world.emit(&"mission_marked", ship, card)
	return true


static func is_marked(world: SimWorld, card: int) -> bool:
	return world.story_flags.get_flag(StringName(_MARKED % card)) == 1


## The mission card whose contact is `contact`, live and visible to the ship, or -1.
static func mission_of_contact(world: SimWorld, ship: int, contact: int) -> int:
	for card: int in world.story.size():
		if (
			world.story.kind[card] == StoryTable.Kind.MISSION
			and world.story.target[card] == contact
			and Story.visible_to(world, card, ship)
			and Story.is_live(world, card)
		):
			return card
	return -1


## A contact the faction's probe found, that no ship of the faction senses itself and that
## has something to say (a hail conversation): its first discovery opens a HAIL card, OPEN,
## on the board of the ship that got the event (FT-COM-002; P15's "new contact to hail").
static func on_discovery(world: SimWorld, ship: int, contact: int) -> void:
	var faction: int = world.faction_of(ship)
	var conv: StringName = world.hail_conversations.get(world.defs[contact].id, &"")
	var flag: StringName = StringName(_OPPORTUNITY % [faction, contact])
	if (
		not world.conversations.has(conv)
		or world.story_flags.get_flag(flag) == 1
		or _senses(world, faction, contact)
	):
		return
	world.story_flags.set_flag(flag, 1)
	var t: StoryTable = world.story
	var card: int = t.add_card(ship, faction, StoryTable.Kind.HAIL)
	t.npc[card] = StringName(world.defs[contact].display_name)
	t.title[card] = "comms.card.opportunity"
	t.conversation[card] = conv
	t.target[card] = contact
	t.rep_faction[card] = world.faction_of(contact)
	world.emit(&"card_posted", ship, card, StoryTable.Kind.HAIL)


## Whether a live ship of the faction has the contact inside its own sensor range.
static func _senses(world: SimWorld, faction: int, contact: int) -> bool:
	for o: int in world.ship_count():
		if world.faction_of(o) != faction or not world.kin.is_alive(o):
			continue
		var reach: float = (
			world.defs[o].sensor_range * DamageSystem.effectiveness(world, o, &"sensors")
		)
		if world.kin.relative(o, contact).length() <= reach:
			return true
	return false


# --- the tick ---


## After the tick's damage: this tick's destructions and discoveries, and the ships that
## docked since the last tick.
static func step(world: SimWorld) -> void:
	if world.story.size() == 0 and world.hail_conversations.is_empty():
		return
	var from: int = world.events.size()
	while from > 0 and world.events[from - 1].tick == world.tick:
		from -= 1
	var seen: Array[SimEvent] = world.events.slice(from)
	for e: SimEvent in seen:
		match e.kind:
			&"destroyed":
				on_destroyed(world, e.ship_id, e.other_id)
			&"contact_detected":
				on_discovery(world, e.ship_id, e.other_id)
	_watch_docks(world)


## Records where each crewed ship is docked without calling on_dock, for the first card
## posted: _watch_docks keeps no record while the board is empty, so a dock made before
## a clearance exists must not count as an arrival once it does.
static func sync_docks(world: SimWorld) -> void:
	for ship: int in world.ship_count():
		if not world.ai.is_enabled(ship):
			world.story_flags.set_flag(
				StringName(_DOCKED % ship), Story.docked_site(world, ship) + 1
			)


## Remembers where each crewed ship is docked and calls on_dock when it arrives.
static func _watch_docks(world: SimWorld) -> void:
	if world.story.size() == 0:
		return
	for ship: int in world.ship_count():
		if world.ai.is_enabled(ship):
			continue
		var flag: StringName = StringName(_DOCKED % ship)
		var site: int = Story.docked_site(world, ship)
		var before: int = world.story_flags.get_flag(flag) - 1
		if site != before:
			world.story_flags.set_flag(flag, site + 1)
			if site >= 0:
				on_dock(world, ship, site)
