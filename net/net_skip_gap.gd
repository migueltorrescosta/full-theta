class_name NetSkipGap
extends RefCounted
## Skip the quiet gap (gp-07, D3): while a fleet's director waits out the gap between two
## encounters (its story flag Director.gap_flag holds the tick the gap ends), each human crew
## player of the fleet may tap Ready (SkipGap{ready}). Once every one of them is Ready, the
## server sets Director.skip_flag to the tick through a logged SetFlagCommand and the director
## picks the next encounter at once, so a replay holds. The voters are the connected human
## sessions with a station or the Captain seat on a ship of the faction in play: viewers and
## bots (stand-ins, client kind "bot") don't vote, and a fleet without a voter doesn't skip.
## Ready clears when the gap ends.
## Crew-chosen sites (E2, w-bzx): the pickers (the human Captains of the fleet, or with none its
## human Comms players) may pick one of the gap's site offers (SitePick{offer}); the server sets
## Director.pick_flag to offer + 1 through a logged SetFlagCommand, and the director plays it
## when the gap ends. Event `gap` {faction, ends_at, ready, voters, offers, pick, pickers}
## (ends_at 0: no gap; ready, voters and pickers are session ids; offers as
## RunDriver.site_offers; pick the chosen offer, 0 for none) goes to the sessions on the
## faction's ships whenever it changes.

## request_rejected reasons: no gap is on for the sender's fleet, or the sender doesn't vote;
## an offer index outside the gap's offers.
const NO_GAP: String = "no_gap"
const BAD_OFFER: String = "bad_offer"

## The owning game, held weakly (it owns this object).
var game: NetGame:
	get:
		return _game.get_ref() as NetGame

## The run driver's offers of a faction's gap (RunDriver.site_offers), set by NetServer; none
## while unset.
var site_offers: Callable = func(_faction: int) -> Array[Dictionary]: return []

var _game: WeakRef
## Faction -> {session id: true} of the Ready players of the current gap.
var _ready: Dictionary[int, Dictionary] = {}
## Faction -> the gap's end tick the Ready set belongs to; the last payload sent.
var _gap: Dictionary[int, int] = {}
var _sent: Dictionary[int, Dictionary] = {}
## Factions whose current gap already has its skip submitted.
var _skipped: Dictionary[int, bool] = {}


func _init(net_game: NetGame) -> void:
	_game = weakref(net_game)
	net_game.add_handler(NetProtocol.Type.SKIP_GAP, on_skip_gap)
	net_game.add_handler(NetProtocol.Type.SITE_PICK, on_site_pick)


## SkipGap{ready}: `no_gap` outside a gap of the sender's fleet, `not_crew` from a non-voter.
func on_skip_gap(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var faction: int = _faction_of(s)
	var reason: String = ""
	if faction < 0 or _ends_at(faction) == 0:
		reason = NO_GAP
	elif not voters(faction).has(s.id):
		reason = NetGame.NOT_CREW
	if game.refuse(s, NetProtocol.Type.SKIP_GAP, reason, {}):
		return
	var ready: Dictionary = _ready.get_or_add(faction, {})
	if msg["ready"]:
		ready[s.id] = true
	else:
		ready.erase(s.id)
	_update(faction)


## SitePick{offer} (w-bzx): `no_gap` outside a gap of the sender's fleet, `not_crew` from a
## non-picker, `bad_offer` for an index outside the offers; else the pick flag is set.
func on_site_pick(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var faction: int = _faction_of(s)
	var offer: int = msg["offer"]
	var reason: String = ""
	if faction < 0 or _ends_at(faction) == 0:
		reason = NO_GAP
	elif not pickers(faction).has(s.id):
		reason = NetGame.NOT_CREW
	elif offer < 0 or offer >= _offers(faction).size():
		reason = BAD_OFFER
	if game.refuse(s, NetProtocol.Type.SITE_PICK, reason, {}):
		return
	var c: SetFlagCommand = SetFlagCommand.new()
	c.flag_name = Director.pick_flag(faction)
	c.value = offer + 1
	game.world.submit(c)


## A new world (NetGame.restart): no gap, no Ready, nothing sent or skipped yet.
func reset() -> void:
	_ready.clear()
	_gap.clear()
	_sent.clear()
	_skipped.clear()


## Each server frame: follows the directors' gap flags and the voters, ends a gap once every
## voter is Ready, and sends the changed `gap` events.
func step() -> void:
	for faction: int in _factions():
		_update(faction)


## The connected human sessions that vote on the faction's gap, in id order.
func voters(faction: int) -> Array[int]:
	return _humans(faction, func(seat: String) -> bool: return seat != StationCatalogue.VIEWER)


## The sessions that may pick the faction's next site (w-bzx), in id order: its human Captains,
## or with none its human players whose seat holds Comms.
func pickers(faction: int) -> Array[int]:
	var out: Array[int] = _humans(
		faction, func(seat: String) -> bool: return seat == StationCatalogue.CAPTAIN
	)
	if out.is_empty():
		out = _humans(
			faction,
			func(seat: String) -> bool: return StationCatalogue.stations_of(seat).has("comms")
		)
	return out


## The connected human (not bot) sessions on ships of the faction in play whose seat passes
## `seat_ok`, in id order.
func _humans(faction: int, seat_ok: Callable) -> Array[int]:
	var out: Array[int] = []
	for id: int in game.by_id:
		var s: NetSession = game.by_id[id]
		if (
			s.connected()
			and s.has_pick()
			and seat_ok.call(s.seat)
			and s.client_kind != "bot"
			and game.world.is_crew_in_play(s.ship)
			and game.world.faction_of(s.ship) == faction
		):
			out.append(id)
	out.sort()
	return out


func _update(faction: int) -> void:
	var ends_at: int = _ends_at(faction)
	if ends_at != _gap.get(faction, 0):
		_gap[faction] = ends_at
		_ready.erase(faction)
		_skipped.erase(faction)
	if ends_at == 0 and not _sent.has(faction):
		return
	var who: Array[int] = []
	var pick_by: Array[int] = []
	var offers: Array[Dictionary] = []
	if ends_at > 0:
		who = voters(faction)
		pick_by = pickers(faction)
		offers = _offers(faction)
	var ready: Array[int] = []
	for id: int in _ready.get(faction, {}):
		if who.has(id):
			ready.append(id)
	ready.sort()
	if (
		ends_at > 0
		and not who.is_empty()
		and ready.size() == who.size()
		and not _skipped.has(faction)
	):
		_skipped[faction] = true
		var c: SetFlagCommand = SetFlagCommand.new()
		c.flag_name = Director.skip_flag(faction)
		c.value = maxi(game.world.tick, 1)
		game.world.submit(c)
	var pick: int = game.world.story_flags.get_flag(Director.pick_flag(faction)) - 1
	var payload: Dictionary = {
		"faction": faction,
		"ends_at": ends_at,
		"ready": ready,
		"voters": who,
		"offers": offers,
		"pick": clampi(pick, 0, maxi(offers.size() - 1, 0)),
		"pickers": pick_by,
	}
	if payload == _sent.get(faction, {}):
		return
	_sent[faction] = payload
	var to: PackedInt32Array = PackedInt32Array()
	for id: int in game.by_id:
		var s: NetSession = game.by_id[id]
		if _faction_of(s) == faction:
			to.append(id)
	game.transport.post_event(to, game.world.tick, NetProtocol.EVENT_GAP, payload)


func _offers(faction: int) -> Array[Dictionary]:
	return site_offers.call(faction)


func _ends_at(faction: int) -> int:
	return game.world.story_flags.get_flag(Director.gap_flag(faction))


## The crew factions of the session's ships, in ship order.
func _factions() -> Array[int]:
	var out: Array[int] = []
	for ship: Dictionary in game.crew_ships():
		if not out.has(int(ship["faction"])):
			out.append(int(ship["faction"]))
	return out


## The faction of the session's ship, -1 without a pick.
func _faction_of(s: NetSession) -> int:
	if not s.has_pick() or not game.crewable(s.ship):
		return -1
	return game.world.faction_of(s.ship)
