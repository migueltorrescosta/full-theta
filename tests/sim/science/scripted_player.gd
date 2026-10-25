class_name ScriptedPlayer
extends RefCounted
## The scripted average player of the minigame timing test (FT-SCI-012, D192): it acts
## through the same commands a client sends, waiting in sim ticks. The constants below
## are the model of an average player (reading the puzzle, turning a dial or tapping a
## node, settling); the owner retunes the game's numbers after the #13 playtest, and
## this model stays the yardstick.

## Seconds to read a scan puzzle and to start turning.
const SCAN_READ_S: float = 1.5
## Dial turn rate (rad/s) and settling time per open axis (s).
const TURN_RATE: float = 1.6
const SETTLE_S: float = 1.0
## Seconds to confirm the match.
const CONFIRM_S: float = 0.8
## Standard deviation of the angle left over on each open axis (rad).
const ANGLE_SD: float = 0.03
## Seconds to read a hack puzzle, per move, and extra per hidden node stepped onto.
const HACK_READ_S: float = 2.0
const MOVE_S: float = 1.0
const BLIND_S: float = 1.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(player_seed: int) -> void:
	_rng.seed = player_seed


## Plays the open scan; returns the seconds from its start to the result event.
func play_scan(w: SimWorld, ship: int = 0) -> float:
	var t: ScienceTable = w.science
	var start: int = w.tick
	var truth: Vector3 = ScienceFixture.solution(w, ship)
	var secs: float = SCAN_READ_S + CONFIRM_S
	var guess: Vector3 = Vector3.ZERO
	for a: int in 3:
		if t.axes[ship] & (1 << a):
			secs += absf(truth[a]) / TURN_RATE + SETTLE_S
			guess[a] = truth[a] + _rng.randfn(0.0, ANGLE_SD)
	SimFixture.run(w, roundi(secs * SimWorld.HZ))
	ScienceFixture.do(w, ScienceFixture.submit_cmd(guess), ship)
	return float(w.tick - start) / SimWorld.HZ


## Plays the open hack along the shortest route; returns the seconds from its start to
## the end of the last move.
func play_hack(w: SimWorld, ship: int = 0) -> float:
	var t: ScienceTable = w.science
	var start: int = w.tick
	var route: Array[int] = ScienceFixture.route(w, ship)
	SimFixture.run(w, roundi(HACK_READ_S * SimWorld.HZ))
	for node: int in route:
		var secs: float = MOVE_S + (BLIND_S if (t.known[ship] & (1 << node)) == 0 else 0.0)
		SimFixture.run(w, roundi(secs * SimWorld.HZ) - 1)
		ScienceFixture.do(w, ScienceFixture.move_cmd(node), ship)
	return float(w.tick - start) / SimWorld.HZ
