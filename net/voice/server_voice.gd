class_name ServerVoice
extends RefCounted
## ServerSession's seam to the host's VoiceService (E10): `voice` is null in net/ tests
## and on a server without voice, and then nothing here does anything. The app sets it
## (ServerMain.make_voice).
## - start(): the run's first Start calls VoiceService.start_session() with the closed
##   set (FT-AUD-018): every ship's name, and every callsign a contact can get in the
##   encounter (KnowledgeSystem.callsign: U, H, F or N and a number up to the count of
##   ships of other factions); M1 has no NPCs.
## - on_event(): the ship computer's alert lines from the sim events of a crewed ship, to
##   the stations concerned (FT-AUD-006; VoiceService.computer_audience): "Hull
##   critical" to every station once the hull is at or under HULL_CRITICAL (re-armed
##   above it), shields low with the percentage, subsystem fault, collision warning.
##   Coalescing and max age come from the line data (content/dialogue/computer.json).

## PROVISIONAL.
const HULL_CRITICAL: float = 0.25
## Sim event kind -> [line id, stations concerned]; hull critical goes to every crew
## station (FT-AUD-006, owner-approved in #7).
const LINES: Dictionary = {
	&"fault": ["computer.subsystem_fault", ["engineering"]],
	&"proximity": ["computer.collision_warning", ["helm"]],
	# --- strand B ---
	&"jump_arrive": ["computer.jump_ready", ["helm"]],
	# --- end strand B ---
}

var voice: VoiceService
## The session's toggle code (ServerSession sets it at every Start; the toggles are
## locked once a run launches): the summaries toggle decides what Helm hears of the shields.
var toggles: String = StationViews.DEFAULT_TOGGLES
var world: SimWorld
# --- strand G1 ---
## NPC display names that join the closed set at Start (FT-AUD-018); strand C fills it.
var npc_names: Array[String] = []
# --- end strand G1 ---
var _started: bool = false
## Ships whose "Hull critical" was said and not re-armed.
var _hull_warned: Dictionary[int, bool] = {}


func _init(sim_world: SimWorld) -> void:
	world = sim_world


## At a Start: the session's voice, once per server (M1's closed set doesn't change, so a
## run reset keeps it).
func start(language: String, crew_factions: Array) -> void:
	if voice == null or _started:
		return
	_started = true
	voice.start_session(language, closed_set(crew_factions))


func closed_set(crew_factions: Array) -> Dictionary:
	var names: Array[String] = []
	var others: int = 0
	for id: int in world.ship_count():
		names.append(world.defs[id].display_name)
		if not crew_factions.has(world.faction_of(id)):
			others += 1
	var callsigns: Array[String] = []
	for prefix: String in ["U", "H", "F", "N"]:
		for n: int in range(1, others + 1):
			callsigns.append(prefix + str(n))
	return {
		"ship_names": names, "callsigns": callsigns, "npc_names": npc_names + Story.npc_names(world)
	}  # strand C


## A sim event of a crewed ship.
func on_event(e: SimEvent) -> void:
	if voice == null:
		return
	if e.kind == &"say":
		_say(e)
	elif e.kind == &"hit" and world.kin.is_alive(e.ship_id):
		var critical: bool = DamageSystem.hull_fraction(world, e.ship_id) <= HULL_CRITICAL
		if critical and not _hull_warned.has(e.ship_id):
			_hull_warned[e.ship_id] = true
			var all: PackedStringArray = PackedStringArray(StationViews.CREW)
			voice.say_computer(e.ship_id, all, "computer.hull_critical")
		elif not critical:
			_hull_warned.erase(e.ship_id)
	elif e.kind == &"shield_low":
		_say_shields_low(e)
	elif LINES.has(e.kind):
		var line: Array = LINES[e.kind]
		voice.say_computer(e.ship_id, PackedStringArray(line[1]), line[0])


# --- strand G1 ---
## A spoken line from the sim (SayCommand): an NPC line (role npc in the dialogue data)
## goes to the holder of that NPC's conversation claim only (FT-AUD-005, FT-COM-006);
## while nobody holds it, it is a subtitle for every Comms holder of the ship
## (PROVISIONAL, Q8; FT-AUD-010). A ship-computer line goes to the stations it concerns
## (FT-AUD-006).
func _say(e: SimEvent) -> void:
	var line_id: String = String(e.tag)
	var line: Dictionary = voice.dialogue.line(line_id)
	if line.is_empty():
		push_warning("ServerVoice: say event for unknown line %s" % line_id)
		return
	var args: Dictionary = e.args.duplicate(true)
	var npc_id: String = str(args.get("npc_id", ""))
	var stations: PackedStringArray = PackedStringArray(args.get("stations", []))
	args.erase("npc_id")
	args.erase("stations")
	if line.get("role", "computer") == "npc":
		# Routed by the card, never by the speaker's name: two ships can meet NPCs of the
		# same name, and a name outlives its run (FT-COM-006).
		npc_id = card_key(int(args.get("card", _card_of(e.ship_id, npc_id))))
		args.erase("card")
		if (voice.npc_audience.call(npc_id) as PackedInt32Array).is_empty():
			var comms: PackedStringArray = PackedStringArray(["comms"])
			var all: PackedInt32Array = voice.computer_audience.call(e.ship_id, comms)
			voice.say_subtitle(line_id, args, all)
		else:
			voice.say_npc(npc_id, line_id, args)
	else:
		voice.say_computer(e.ship_id, stations, line_id, args)


# --- end strand G1 ---
## The key VoiceService.npc_audience takes for a card's conversation.
static func card_key(card: int) -> String:
	return "card:%d" % card


## The card a key names, or -1.
static func card_of_key(key: String) -> int:
	return int(key.trim_prefix("card:")) if key.begins_with("card:") else -1


## The newest live card with an open conversation that `npc` speaks on, on the ship's
## board (a line said by name, not by Story: a scenario's message()); -1 for none.
func _card_of(ship: int, npc: String) -> int:
	for card: int in range(world.story.size() - 1, -1, -1):
		if (
			String(world.story.npc[card]) == npc
			and world.story.node[card] != StoryTable.NO_TEXT
			and Story.is_live(world, card)
			and Story.visible_to(world, card, ship)
		):
			return card
	return -1


## "Shields low" follows the text alert's summaries rule (D224, FT-PAIR-019): Engineering
## always hears the exact percentage; Helm hears it exact (Easy), as its band's midpoint
## (Normal) or with no number (Hard, "computer.shields_low_plain"); never Comms.
func _say_shields_low(e: SimEvent) -> void:
	var exact: int = roundi(e.value * 100.0)
	var eng: PackedStringArray = PackedStringArray(["engineering"])
	voice.say_computer(e.ship_id, eng, "computer.shields_low", {"pct": exact})
	var seen: float = StationViews.event_value("helm", e.kind, e.value, toggles)
	if seen <= 0.0:
		voice.say_computer(e.ship_id, PackedStringArray(["helm"]), "computer.shields_low_plain")
	else:
		var args: Dictionary = {"pct": roundi(seen * 100.0)}
		voice.say_computer(e.ship_id, PackedStringArray(["helm"]), "computer.shields_low", args)


## The run reset: the new world, every hull alert re-armed, and the old run's lines
## still queued (stitched lines waiting for a name, free text being synthesised) dropped.
func restart(sim_world: SimWorld) -> void:
	world = sim_world
	_hull_warned.clear()
	if voice != null:
		voice.flush_lines()
