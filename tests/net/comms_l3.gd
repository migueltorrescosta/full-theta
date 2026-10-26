class_name CommsL3
extends RefCounted
## Helpers for the Comms L3 tests: wiring a server's world with the scenario
## data app/ will load, posting cards, and sending a command to learn its verdict.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY
const S = StationViews.Section


## Wires the server's world (conversations, markets, modules), gives the ship credits, docks
## it at the Kappa site and posts Kappa's offer card (id 0).
static func offer(server: NetServer, credits: int = 1000) -> void:
	var w: SimWorld = StoryFixture.wire(server.world)
	w.economy.credits[PLAYER] = credits
	StoryFixture.dock(w, PLAYER)
	var card: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER, &"", StoryFixture.SITE)
	card.ship_id = PLAYER
	card.source = SimCommand.Source.SERVER
	w.submit(card)


## Posts a card to the player's ship from the server.
static func post(server: NetServer, card: PostCardCommand) -> void:
	card.ship_id = PLAYER
	card.source = SimCommand.Source.SERVER
	server.world.submit(card)


## Sends a command; returns the CommandRejected reason, or "" once the sim applied it.
static func verdict(h: NetHarness, server: NetServer, c: NetClient, cmd: Dictionary) -> String:
	var from: int = h.mark(c)
	var seq: int = c.command(cmd)
	var tick: int = server.world.tick
	var reason: Array[String] = []
	var done: Callable = func() -> bool:
		for e: Dictionary in h.events[c].slice(from):
			if e["type"] == NetProtocol.EVENT_COMMAND_REJECTED and e["payload"]["seq"] == seq:
				reason.append(e["payload"]["reason"])
				return true
		return server.world.tick > tick + 6 and server.session._pending.is_empty()
	await h.until(done)
	await h.wait(100)
	done.call()
	return reason[0] if not reason.is_empty() else ""


## The client's COMMS block, or {}.
static func block(c: NetClient) -> Dictionary:
	return c.view.blocks.get(S.COMMS, {})


## The card row with that id in the client's COMMS block, or {}.
static func card_row(c: NetClient, id: int) -> Dictionary:
	for row: Dictionary in block(c).get("cards", []):
		if row["id"] == id:
			return row
	return {}
