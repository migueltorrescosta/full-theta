class_name StoryRules
extends RefCounted
## The cooperation rules of Comms with other stations (#10): what STORY does
## when the rest of the crew acts. Their state is typed columns: a card's on StoryTable,
## a ship's dock watch on StoryShipTable and a faction's about a contact on
## KnowledgeTable; scenario flags (StoryFlagTable) are not theirs. All of them apply at
## every difficulty
## (FT-PAIR-014); the toggles only decide what a screen shows.
## - P5 approach lanes (FT-PAIR-001): a clearance card carries a window; docking at its
##   site inside the window is cleared, docking without one loses reputation.
## - P9 surrender (FT-MIS-042): a conversation roll whose chance rises with the contact's
##   engine damage, and a reputation loss for destroying a surrendered contact.
## - P12 terms: an offer can need power on a subsystem, which the ship may not have.
## - P14 scan facts: a scan that reaches a fact's confidence teaches the faction the fact.
## - Dock markets (D86, FT-MIS-036): a ship docking at a site with a market gets that market's
##   OFFER card on its board, which lapses when it undocks.
## - P15 locating: Relay marks a mission, and a probe that finds a contact that can be
##   hailed opens an opportunity on Comms' board.

## Reputation draws (content/economy/rep/).
const UNCLEARED: StringName = &"rep.uncleared_approach"
const SURRENDER_KILL: StringName = &"rep.destroy_surrendered"

# --- P5: approach lanes ---


## Makes the card a clearance: after it is accepted, the lane opens `open_s` later and
## stays open `length_s`.
static func set_lane(world: SimWorld, card: int, open_s: float, length_s: float) -> void:
	if not length_s > 0.0:
		return
	world.story.lane_open[card] = maxi(0, SimRate.ticks(open_s))
	world.story.lane_len[card] = SimRate.ticks(length_s)


static func is_lane(world: SimWorld, card: int) -> bool:
	return _is_card(world, card) and world.story.lane_len[card] > 0


## Whether the card id names a posted card (the readers below take any id).
static func _is_card(world: SimWorld, card: int) -> bool:
	return card >= 0 and card < world.story.size()


## The accepted clearance's window as [first tick, last tick], or [] while the card isn't
## an accepted clearance.
static func lane_window(world: SimWorld, card: int) -> Array[int]:
	var out: Array[int] = []
	var t: StoryTable = world.story
	if is_lane(world, card) and t.lane_t0[card] > 0:
		var first: int = t.lane_t0[card] - 1 + t.lane_open[card]
		out.assign([first, first + t.lane_len[card]])
	return out


## Called when a card is accepted: a clearance starts its clock.
static func on_accept(world: SimWorld, card: int) -> void:
	if is_lane(world, card):
		world.story.lane_t0[card] = world.tick + 1


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
			world, ship, world.story.owner_faction[card], world.story.rep_faction[card], UNCLEARED
		)
	world.emit(&"dock_uncleared", ship, card, delta)


# --- settling a card ---


## Settles an accepted card: success pays the reward and draws the card's reputation
## change; failure draws "<interaction>.fail" if there is one (FT-COM-005, FT-MIS-021). A
## partial success (the encounter's time ran out) pays RunDef.partial_pay of the reward,
## rounded, and changes no standing.
static func settle(
	world: SimWorld, ship: int, card: int, success: bool, partial: bool = false
) -> void:
	var t: StoryTable = world.story
	Story.set_state(
		world, ship, card, StoryTable.State.DONE if success else StoryTable.State.FAILED
	)
	var dist: StringName = t.rep_interaction[card]
	if success and partial:
		var share: float = world.run_def.partial_pay if world.run_def != null else 1.0
		Economy.add_credits(world, ship, roundi(t.reward[card] * share))
		return
	if success:
		Economy.add_credits(world, ship, t.reward[card])
	elif dist != &"":
		dist = StringName(String(dist) + ".fail")
	if dist != &"" and t.rep_faction[card] >= 0:
		Reputation.change(world, ship, t.owner_faction[card], t.rep_faction[card], dist)


# --- P9: surrender ---


## The share of a contact's engines' effectiveness that is gone (0 to 1).
static func engine_damage(world: SimWorld, contact: int) -> float:
	return 1.0 - DamageSystem.effectiveness(world, contact, &"engines")


## The chance that a contact surrenders when asked: `base` plus `per_damage` times its
## engine_damage, at most `cap` (all dimensionless). Prior engine damage raises it
## (FT-PAIR-004 P9).
static func surrender_chance(world: SimWorld, contact: int, params: Dictionary) -> float:
	var chance: float = (
		float(params.get("base", 0.0))
		+ float(params.get("per_damage", 0.0)) * engine_damage(world, contact)
	)
	return clampf(chance, 0.0, float(params.get("cap", 1.0)))


## Comms asked the card's contact to surrender (the conversation's surrender effect, #35 A4):
## rolls with the chance times `refusal_factor` (default 1) once for each earlier refusal of
## this contact to the card's faction; a refusal counts one more and closes the ask for
## `retry_s` seconds (default 0; the option's surrender_ready requirement).
static func ask_surrender(world: SimWorld, ship: int, card: int, params: Dictionary) -> void:
	var t: StoryTable = world.story
	var k: KnowledgeTable = world.knowledge
	var row: int = k.ensure_contact(t.owner_faction[card], t.target[card])
	var scale: float = pow(float(params.get("refusal_factor", 1.0)), k.surrender_refusals[row])
	if roll_surrender(world, ship, card, params, scale):
		return
	k.surrender_refusals[row] += 1
	k.surrender_reopen[row] = world.tick + SimRate.ticks(float(params.get("retry_s", 0.0)))


## Whether the faction may ask the contact to surrender again: no refusal in the last
## retry_s seconds.
static func surrender_ready(world: SimWorld, faction: int, contact: int) -> bool:
	var row: int = world.knowledge.row_for(faction, contact)
	return row < 0 or world.tick >= world.knowledge.surrender_reopen[row]


## Draws from the "surrender" stream with the chance (times `scale`) and sets the faction's
## intent for the card's contact to SURRENDERING, or HOSTILE when it refuses. Emits
## surrender_roll (value the chance, tag &"yes" or &"no"). Returns whether it said yes.
static func roll_surrender(
	world: SimWorld, ship: int, card: int, params: Dictionary, scale: float = 1.0
) -> bool:
	var t: StoryTable = world.story
	var chance: float = surrender_chance(world, t.target[card], params) * scale
	var yes: bool = world.rng.stream(&"surrender").randf() < chance
	var row: int = world.knowledge.ensure_contact(t.owner_faction[card], t.target[card])
	world.knowledge.intent[row] = (
		KnowledgeTable.Intent.SURRENDERING if yes else KnowledgeTable.Intent.HOSTILE
	)
	world.emit(
		&"surrender_roll", ship, t.target[card], chance, Vector3.ZERO, &"yes" if yes else &"no"
	)
	return yes


## A ship was destroyed by `source`: if the source's faction had the victim as surrendering,
## the source loses reputation with the victim's faction (rep.destroy_surrendered) and the
## debrief gets a line (event surrender_killed, tag debrief.surrender_killed, value the
## change). An accepted "disable, do not destroy" contract on the victim fails.
static func on_destroyed(world: SimWorld, victim: int, source: int) -> void:
	if world.has_ship(source):
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
		world.story.need_subsystem[card] = subsystem
		world.story.need_pips[card] = pips


## The card's need as {subsystem, pips}, or {}.
static func need_of(world: SimWorld, card: int) -> Dictionary:
	var t: StoryTable = world.story
	if not _is_card(world, card) or t.need_pips[card] <= 0:
		return {}
	return {"subsystem": t.need_subsystem[card], "pips": t.need_pips[card]}


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
	if (
		world.science_def != null
		and (conf >= ScienceKnowledge.threshold(world.science_def, ScienceKnowledge.CARGO))
	):
		Story.learn_fact(world, faction, contact, "cargo")


# --- P15: locating missions and opportunities ---


## Relay marked the mission's place: Comms' card shows the mark icon under mission_icon.
static func mark_mission(world: SimWorld, ship: int, card: int) -> bool:
	if not Story.visible_to(world, card, ship) or not Story.is_live(world, card):
		return false
	world.story.marked[card] = 1
	world.emit(&"mission_marked", ship, card)
	return true


static func is_marked(world: SimWorld, card: int) -> bool:
	return _is_card(world, card) and world.story.marked[card] == 1


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
	var k: KnowledgeTable = world.knowledge
	var row: int = k.row_for(faction, contact)
	if (
		not world.conversations.has(conv)
		or (row >= 0 and k.hail_opened[row] == 1)
		or _senses(world, faction, contact)
	):
		return
	k.hail_opened[k.ensure_contact(faction, contact)] = 1
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
		if world.faction_of(o) != faction:
			continue
		var reach: float = KnowledgeSystem.sensor_reach(world, o)
		if reach > 0.0 and world.kin.relative(o, contact).length() <= reach:
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
			world.story_ships.seen_dock[ship] = Story.docked_site(world, ship)


## Remembers where each crewed ship is docked and calls on_dock when it arrives.
static func _watch_docks(world: SimWorld) -> void:
	if world.story.size() == 0 and world.site_markets.is_empty():
		return
	for ship: int in world.ship_count():
		if world.ai.is_enabled(ship):
			continue
		var site: int = Story.docked_site(world, ship)
		var before: int = world.story_ships.seen_dock[ship]
		if site != before:
			world.story_ships.seen_dock[ship] = site
			if before >= 0:
				_close_dock_offer(world, ship)
			if site >= 0:
				on_dock(world, ship, site)
				_offer_market(world, ship, site)


## A ship docked at a site with a market: its OFFER card for the site, which Trade.market needs
## (D86: modules and goods are bought while docked, via Comms).
static func _offer_market(world: SimWorld, ship: int, site: int) -> void:
	if not world.site_markets.has(site) or world.ai.is_enabled(ship):
		return
	var t: StoryTable = world.story
	var card: int = t.add_card(ship, world.faction_of(ship), StoryTable.Kind.OFFER)
	t.title[card] = "comms.card.offer"
	t.site[card] = site
	t.requires_docked[card] = 1
	world.story_ships.dock_offer[ship] = card
	world.emit(&"card_posted", ship, card, StoryTable.Kind.OFFER)


## The ship undocked: its market card lapses.
static func _close_dock_offer(world: SimWorld, ship: int) -> void:
	var card: int = world.story_ships.dock_offer[ship]
	if card < 0:
		return
	world.story_ships.dock_offer[ship] = -1
	if Story.is_live(world, card):
		Story.set_state(world, ship, card, StoryTable.State.EXPIRED)
