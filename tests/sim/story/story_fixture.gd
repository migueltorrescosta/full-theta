class_name StoryFixture
extends RefCounted
## Worlds and helpers for the STORY, economy and module suites (strand C). Every ship is
## built through spawn(), the one place that calls SimWorld.spawn_ship, so the space-id
## removal (B0) changes one line.

const BLUE: int = 1
const RED: int = 2
const SITE: int = 3
const KAPPA: StringName = &"kappa"

static var _content: Dictionary = {}


## Spawns a ship `offset` m from the origin.
static func spawn(
	world: SimWorld, def: ShipDef, faction: int, offset: Vector3 = Vector3.ZERO
) -> int:
	return world.spawn_ship(def, faction, offset)


## A world wired like app/ will wire it: conversations, markets, modules, reputation
## distributions, the raider answering hails with the trader conversation, and Kappa's
## market at SITE. Ships are the caller's.
static func world(world_seed: int = 1) -> SimWorld:
	return wire(SimWorld.new(world_seed, "test"))


## Gives a world the scenario data app/ will load (the L3 tests wire the server's world).
static func wire(w: SimWorld) -> SimWorld:
	var c: Dictionary = content()
	w.conversations = c["conversations"]
	w.hail_conversations = {&"m1_raider": &"conv.trader_bluff"}
	w.markets = c["markets"]
	w.module_defs.assign(c["modules"])
	w.rep_dists = c["rep_dists"]
	w.site_markets = {SITE: KAPPA}
	return w


## BLUE's corvette at the origin and RED's raider `range_m` ahead, after a step so they
## detect each other.
static func duel(world_seed: int = 1, range_m: float = 5000.0) -> SimWorld:
	var w: SimWorld = world(world_seed)
	spawn(w, TestDefs.corvette(), BLUE)
	spawn(w, TestDefs.raider(), RED, Vector3(0.0, 0.0, -range_m))
	w.step()
	return w


## Docks the ship at a site for real: the world gets dockable sites at the origin up to
## `site` (ids below it exist, the ship is moved there if it is out of dock range and
## stopped), then a DockCommand is applied without stepping.
static func dock(w: SimWorld, ship: int, site: int = SITE) -> void:
	while w.sites.size() <= site:
		var d: SiteDef = SiteDef.new()
		d.id = StringName("fx%d" % w.sites.size())
		d.name_key = "site.kestrel_yard"
		d.radius_m = 3000.0
		d.dockable = true
		d.dock_range_m = 1500.0
		d.dock_max_speed = 10.0
		w.add_site(d)
	if SiteTable.offset_to(w, ship, site).length() > w.sites.dock_range[site]:
		w.kin.place(ship, w.sites.pos_x[site], w.sites.pos_y[site], w.sites.pos_z[site])
	w.helm.docked_site[ship] = -1  # a ship docked elsewhere lets go first
	w.kin.vel[ship] = Vector3.ZERO
	var c: DockCommand = DockCommand.new()
	c.ship_id = ship
	c.site_id = site
	# Applied at once, not queued, so a world built at tick 0 stays at tick 0.
	var docked: bool = c.apply(w)
	assert(docked, "StoryFixture.dock: the dock was refused")


## Resets a ship in place.
static func reset(w: SimWorld, ship: int) -> void:
	w.reset_ship(ship)


## Submits a command from a ship and steps one tick; returns whether it was accepted.
static func run(w: SimWorld, ship: int, c: SimCommand) -> bool:
	c.ship_id = ship
	w.submit(c)
	w.step()
	return c.accepted


## Posts a card to the ship and returns its id.
static func post(w: SimWorld, ship: int, spec: PostCardCommand) -> int:
	var id: int = Story.next_card_id(w)
	assert(run(w, ship, spec))
	return id


## A card with defaults: kind, conversation, and optionally a market site.
static func card(kind: StoryTable.Kind, conv: StringName = &"", site: int = -1) -> PostCardCommand:
	var c: PostCardCommand = PostCardCommand.new()
	c.card_kind = kind
	c.conversation_id = conv
	c.npc_id = &"Harbour Master"
	c.title_key = "comms.card.offer"
	c.site = site
	return c


## The events of one kind drained from the world since the last drain.
static func events(w: SimWorld, kind: StringName) -> Array[SimEvent]:
	return SimFixture.of_kind(w.drain_events(), kind)


static func content() -> Dictionary:
	if _content.is_empty():
		var modules: Array[ModuleDef] = []
		for path: String in DefLibrary.list_tres("res://content/modules"):
			modules.append(load(path) as ModuleDef)
		var dists: Dictionary[StringName, RepDistDef] = {}
		for path: String in DefLibrary.list_tres("res://content/economy/rep"):
			var d: RepDistDef = load(path) as RepDistDef
			dists[d.id] = d
		var markets: Dictionary[StringName, MarketDef] = {}
		for path: String in DefLibrary.list_tres("res://content/economy/markets"):
			var m: MarketDef = load(path) as MarketDef
			markets[m.id] = m
		_content = {
			"conversations": ConversationLibrary.load_dir(),
			"modules": modules,
			"rep_dists": dists,
			"markets": markets,
		}
	return _content
