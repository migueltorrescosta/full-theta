class_name SessionRules
extends RefCounted
## The rules of one multi-ship session (#11, E11, E12; owner M4-Q1 to M4-Q10, 2026-10-28):
## the scenario mode the host picks in the lobby, the team win rule, each side's relaunch
## policy and where eliminated crew go. RunSetup hands it to the world (SimWorld.rules);
## OutcomeSystem.session_outcome reads it, the director keys on it and the server sends it
## in the lobby. Pure value: no defs, no I/O. A single-ship run is COOP with one slot.
##
## Modes:
## - COOP: one fleet run of allied ships, one faction, one director, one final objective
##   (FT-MIS-013, FT-MIS-023, M4-Q1).
## - RACE: every ship its own faction; one seeded encounter list, each ship at its own copy of
##   each site; the first ship to complete the final objective wins; ship-to-ship combat is
##   allowed (FT-MIS-032, M4-Q5).
## - LAST_STANDING: every ship its own faction; the last ship not destroyed wins; the director
##   sends growing raider waves at every surviving ship (FT-MIS-033, M4-Q7).
## - TEAMS: two teams, one faction each; the host picks the win rule (FT-MIS-034, M4-Q6).
## - HOLDOUT: two teams; a small side relaunches without limit, the other has finite lives,
##   scored by how long the finite side lasts (M4-Q2).

enum Mode { COOP, RACE, LAST_STANDING, TEAMS, HOLDOUT }
## The TEAMS win rule the host picks (M4-Q6).
enum TeamWin { LAST_TEAM_STANDING, FIRST_TO_FINISH }
## Where an eliminated crew goes (FT-MIS-030, D91): FRIENDLY_VIEWER, the main screen of a
## surviving friendly ship, or the lobby scoreboard when none survives; SCOREBOARD always the
## lobby scoreboard.
enum Destination { FRIENDLY_VIEWER, SCOREBOARD }

## Wire and log names, in enum order.
const MODE_NAMES: Array[String] = ["coop", "race", "last_standing", "teams", "holdout"]
const TEAM_WIN_NAMES: Array[String] = ["last_team_standing", "first_to_finish"]
const DESTINATION_NAMES: Array[String] = ["friendly_viewer", "scoreboard"]
## Most crewable ships in one session (FT-GEN-001, M4-Q3).
const MAX_SHIPS: int = 6
## Crew factions by side: the first is the co-op faction (M1Encounter.PLAYER_FACTION); the
## others stay clear of the NPC factions the scenarios use (2 to 4).
const CREW_FACTIONS: Array[int] = [1, 11, 12, 13, 14, 15]
## HOLDOUT's sides: the small side relaunches without limit; the finite side has
## HOLDOUT_LIVES relaunches. PROVISIONAL (#13 tunes it).
const HOLDOUT_SMALL_TEAM: int = 0
const HOLDOUT_FINITE_TEAM: int = 1
const HOLDOUT_LIVES: int = 3

var mode: Mode = Mode.COOP
## Read in TEAMS only.
var team_win: TeamWin = TeamWin.LAST_TEAM_STANDING
var eliminated_to: Destination = Destination.FRIENDLY_VIEWER
## Team -> its relaunch policy; a team missing here uses default_relaunch.
var relaunch: Dictionary[int, RelaunchPolicy] = {}
var default_relaunch: RelaunchPolicy = RelaunchPolicy.none()


## The rules a mode starts with; the host's options then change team_win (TEAMS) and the
## finite side's lives (HOLDOUT).
static func of_mode(m: Mode) -> SessionRules:
	var r: SessionRules = SessionRules.new()
	r.mode = m
	match m:
		Mode.RACE, Mode.LAST_STANDING:
			r.eliminated_to = Destination.SCOREBOARD
		Mode.HOLDOUT:
			r.relaunch[HOLDOUT_SMALL_TEAM] = RelaunchPolicy.unlimited()
			r.relaunch[HOLDOUT_FINITE_TEAM] = RelaunchPolicy.of_lives(HOLDOUT_LIVES)
	return r


## Any mode but COOP: no host pause (FT-MIS-040), enemies never take over (M4-Q8), a give-up
## is a forfeit (M4-Q10).
func is_pvp() -> bool:
	return mode != Mode.COOP


## Whether sides are teams of several ships (TEAMS, HOLDOUT) rather than one ship each.
func has_teams() -> bool:
	return mode == Mode.TEAMS or mode == Mode.HOLDOUT


func relaunch_for(team: int) -> RelaunchPolicy:
	return relaunch.get(team, default_relaunch)


## The faction of the slot at `index` on `team`: one faction in COOP, one per team in TEAMS
## and HOLDOUT, one per ship in RACE and LAST_STANDING. Allies share it (FT-ARC-018).
func faction_for(index: int, team: int) -> int:
	match mode:
		Mode.COOP:
			return CREW_FACTIONS[0]
		Mode.TEAMS, Mode.HOLDOUT:
			return CREW_FACTIONS[clampi(team, 0, CREW_FACTIONS.size() - 1)]
	return CREW_FACTIONS[clampi(index, 0, CREW_FACTIONS.size() - 1)]


## Why the slots can't start under these rules, or []: 1 to MAX_SHIPS slots; with teams,
## teams 0 and 1 only and at least one ship a side (M4-Q6); the factions faction_for gives.
func slot_errors(slots: Array[ShipSlot]) -> Array[String]:
	var out: Array[String] = []
	if slots.is_empty() or slots.size() > MAX_SHIPS:
		out.append("a session has 1 to %d ships, got %d" % [MAX_SHIPS, slots.size()])
	if has_teams():
		var per_team: Array[int] = [0, 0]
		for s: ShipSlot in slots:
			if s.team < 0 or s.team > 1:
				out.append("ship %s is on team %d; teams are 0 and 1" % [s.name, s.team])
			else:
				per_team[s.team] += 1
		if per_team[0] == 0 or per_team[1] == 0:
			out.append("each team needs at least one ship")
	elif mode != Mode.COOP and slots.size() < 2:
		out.append("%s needs at least 2 ships" % MODE_NAMES[mode])
	for i: int in slots.size():
		if slots[i].faction != faction_for(i, slots[i].team):
			out.append(
				(
					"ship %s has faction %d, expected %d"
					% [slots[i].name, slots[i].faction, faction_for(i, slots[i].team)]
				)
			)
	for team: int in relaunch:
		out.append_array(relaunch[team].errors())
	return out


func to_dict() -> Dictionary:
	var policies: Dictionary = {}
	for team: int in relaunch:
		policies[team] = relaunch[team].to_dict()
	return {
		"mode": MODE_NAMES[mode],
		"team_win": TEAM_WIN_NAMES[team_win],
		"eliminated_to": DESTINATION_NAMES[eliminated_to],
		"relaunch": policies,
		"default_relaunch": default_relaunch.to_dict(),
	}
