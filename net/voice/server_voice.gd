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
	&"shield_low": ["computer.shields_low", ["helm", "engineering"]],
	&"fault": ["computer.subsystem_fault", ["engineering"]],
	&"proximity": ["computer.collision_warning", ["helm"]],
}

var voice: VoiceService
var world: SimWorld
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
	return {"ship_names": names, "callsigns": callsigns, "npc_names": []}


## A sim event of a crewed ship.
func on_event(e: SimEvent) -> void:
	if voice == null:
		return
	if e.kind == &"hit" and world.kin.is_alive(e.ship_id):
		var critical: bool = DamageSystem.hull_fraction(world, e.ship_id) <= HULL_CRITICAL
		if critical and not _hull_warned.has(e.ship_id):
			_hull_warned[e.ship_id] = true
			var all: PackedStringArray = PackedStringArray(StationViews.CREW)
			voice.say_computer(e.ship_id, all, "computer.hull_critical")
		elif not critical:
			_hull_warned.erase(e.ship_id)
	elif LINES.has(e.kind):
		var line: Array = LINES[e.kind]
		var args: Dictionary = {}
		if e.kind == &"shield_low":
			args["pct"] = roundi(e.value * 100.0)
		voice.say_computer(e.ship_id, PackedStringArray(line[1]), line[0], args)


## The run reset: the new world, every hull alert re-armed, and the old run's lines
## still queued (stitched lines waiting for a name, free text being synthesised) dropped.
func restart(sim_world: SimWorld) -> void:
	world = sim_world
	_hull_warned.clear()
	if voice != null:
		voice.flush_lines()
