class_name ScienceHand
extends RefCounted
## The scripted Science station of the pair scenarios (P3, P7, P13): the average player
## of the minigame timing test (ScriptedPlayer's model, FT-SCI-012, D192) acting through
## the commands a client sends, one tick at a time. It waits until its faction detects the
## contact (by its own sensors or a probe's bubble), opens a scan, solves it after the
## time the player model needs for the open axes, and, when asked, hacks a subsystem
## along the shortest route and retries once the trace has failed it. One instance plays
## one run: build a fresh one per run (act() is the crew Callable).

enum Phase { WAIT, SCAN, HACK, DONE }

## Hack this subsystem of the contact after the scan; &"" for a scan only.
var hack_subsystem: StringName = &""
## When set, a Callable(world) -> bool that must hold before the script opens its scan
## (P3: Science waits until Helm has brought the ship to the scan-position mark).
var start_gate: Callable = Callable()

var _ship: int
var _contact: int
var _phase: Phase = Phase.WAIT
var _due: int = 0
var _submitted: bool = false
var _route: Array[int] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(ship: int, contact: int, player_seed: int) -> void:
	_ship = ship
	_contact = contact
	_rng.seed = player_seed


## Whether the script has nothing left to do.
func is_done() -> bool:
	return _phase == Phase.DONE


## The crew Callable's body: called every tick before the world steps.
func act(w: SimWorld) -> void:
	match _phase:
		Phase.WAIT:
			_wait(w)
		Phase.SCAN:
			_scan(w)
		Phase.HACK:
			_hack(w)


func _wait(w: SimWorld) -> void:
	if not KnowledgeSystem.is_detected(w, w.faction_of(_ship), _contact):
		return
	if w.science.kind[_ship] != ScienceTable.Session.NONE:
		return
	if start_gate.is_valid() and not bool(start_gate.call(w)):
		return
	if _wants_scan(w):
		var c: ScienceScanCommand = ScienceFixture.scan_cmd(_contact)
		c.ship_id = _ship
		w.submit(c)
		_phase = Phase.SCAN
		_due = -1
		_submitted = false
	else:
		var h: ScienceHackCommand = ScienceFixture.hack_cmd(hack_subsystem, _contact)
		h.ship_id = _ship
		w.submit(h)
		_phase = Phase.HACK
		_route = []
		_due = -1
		_submitted = false


## A scan is wanted while the hack's access (D59) is not yet unlocked, or when there is
## no hack to do and nothing has been scanned.
func _wants_scan(w: SimWorld) -> bool:
	var faction: int = w.faction_of(_ship)
	if hack_subsystem == &"":
		return ScienceKnowledge.confidence(w, faction, _contact) <= 0.0
	return not ScienceKnowledge.revealed(w, faction, _contact, ScienceKnowledge.HACK)


func _scan(w: SimWorld) -> void:
	var t: ScienceTable = w.science
	if t.kind[_ship] != ScienceTable.Session.SCAN:
		# Submitted, the result is in KNOW; else the command was refused, ask again.
		if _submitted:
			_phase = Phase.WAIT if hack_subsystem != &"" else Phase.DONE
		else:
			_phase = Phase.WAIT
		return
	var truth: Vector3 = ScienceFixture.solution(w, _ship)
	if _due < 0:
		var secs: float = ScriptedPlayer.SCAN_READ_S + ScriptedPlayer.CONFIRM_S
		for a: int in 3:
			if t.axes[_ship] & (1 << a):
				secs += absf(truth[a]) / ScriptedPlayer.TURN_RATE + ScriptedPlayer.SETTLE_S
		_due = w.tick + roundi(secs * SimWorld.HZ)
	if w.tick < _due:
		return
	var guess: Vector3 = Vector3.ZERO
	for a: int in 3:
		if t.axes[_ship] & (1 << a):
			guess[a] = truth[a] + _rng.randfn(0.0, ScriptedPlayer.ANGLE_SD)
	var submit: ScienceScanSubmitCommand = ScienceFixture.submit_cmd(guess)
	submit.ship_id = _ship
	w.submit(submit)
	_submitted = true


func _hack(w: SimWorld) -> void:
	var t: ScienceTable = w.science
	if t.kind[_ship] != ScienceTable.Session.HACK:
		# The last move opened the window; otherwise the hack was refused or traced: retry.
		_phase = Phase.DONE if _submitted else Phase.WAIT
		return
	if _due < 0:
		_route = ScienceFixture.route(w, _ship)
		_due = w.tick + roundi(ScriptedPlayer.HACK_READ_S * SimWorld.HZ)
	if w.tick < _due or _submitted:
		return
	var node: int = _route.pop_front()
	var blind: float = ScriptedPlayer.BLIND_S if (t.known[_ship] & (1 << node)) == 0 else 0.0
	var move: ScienceHackMoveCommand = ScienceFixture.move_cmd(node)
	move.ship_id = _ship
	w.submit(move)
	_due = w.tick + roundi((ScriptedPlayer.MOVE_S + blind) * SimWorld.HZ)
	_submitted = _route.is_empty()
