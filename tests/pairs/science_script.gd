class_name ScienceScript
extends RefCounted
## The scripted Science station of the pair scenarios (P7, Hack alpha): it scans a
## contact, then (when `hack_subsystem` is set) hacks that subsystem, through the same
## commands a client sends, one call to act() per tick. Its timing is the average
## player of the minigame test (ScriptedPlayer): read the puzzle, turn the dial about
## each open axis, settle, confirm; read the route, one move a second and a second more
## onto a hidden node. It solves both puzzles exactly, as the average player model does
## (ANGLE_SD is its only error and is left out here, so a run is the same on every seed).
## One instance plays one run; make a fresh one per run.

enum Phase { IDLE, SCANNING, SCANNED, HACKING, DONE }

var ship: int
var contact: int
## Tick the scan starts at.
var start_tick: int
## Subsystem id to hack after the scan, or &"" for a scan only.
var hack_subsystem: StringName

var _phase: Phase = Phase.IDLE
var _due: int = -1
var _route: Array[int] = []
var _next: int = 0


func _init(ship_id: int, contact_id: int, start: int, hack: StringName = &"") -> void:
	ship = ship_id
	contact = contact_id
	start_tick = start
	hack_subsystem = hack


## Whether the script has finished everything it was asked to do.
func finished() -> bool:
	return _phase == Phase.DONE


## This tick's commands; call it right before world.step().
func act(w: SimWorld) -> void:
	var t: ScienceTable = w.science
	match _phase:
		Phase.IDLE:
			if w.tick >= start_tick:
				var scan: ScienceScanCommand = ScienceScanCommand.new()
				scan.ship_id = ship
				scan.contact = contact
				w.submit(scan)
				_phase = Phase.SCANNING
		Phase.SCANNING:
			if t.kind[ship] != ScienceTable.Session.SCAN:
				if _due >= 0:
					_phase = Phase.SCANNED if hack_subsystem != &"" else Phase.DONE
				return
			if _due < 0:
				_due = w.tick + _scan_ticks(w)
			if w.tick >= _due:
				var submit: ScienceScanSubmitCommand = ScienceScanSubmitCommand.new()
				submit.ship_id = ship
				var angles: Vector3 = ScienceFixture.solution(w, ship)
				submit.ax = angles.x
				submit.ay = angles.y
				submit.az = angles.z
				w.submit(submit)
				_due = w.tick
		Phase.SCANNED:
			var hack: ScienceHackCommand = ScienceHackCommand.new()
			hack.ship_id = ship
			hack.contact = contact
			hack.subsystem_id = hack_subsystem
			w.submit(hack)
			_phase = Phase.HACKING
			_due = -1
		Phase.HACKING:
			_step_hack(w, t)
		Phase.DONE:
			pass


func _step_hack(w: SimWorld, t: ScienceTable) -> void:
	if t.kind[ship] != ScienceTable.Session.HACK:
		if _due >= 0:
			_phase = Phase.DONE
		return
	if _due < 0:
		_route = ScienceFixture.route(w, ship)
		_next = 0
		_due = w.tick + roundi((ScriptedPlayer.HACK_READ_S + _move_secs(t)) * SimWorld.HZ)
	if w.tick >= _due and _next < _route.size():
		var move: ScienceHackMoveCommand = ScienceHackMoveCommand.new()
		move.ship_id = ship
		move.node = _route[_next]
		w.submit(move)
		_next += 1
		_due = w.tick + roundi(_move_secs(t) * SimWorld.HZ)


## Seconds to the next move: a second, and a second more onto a hidden node.
func _move_secs(t: ScienceTable) -> float:
	if _next >= _route.size():
		return 0.0
	var hidden: bool = (t.known[ship] & (1 << _route[_next])) == 0
	return ScriptedPlayer.MOVE_S + (ScriptedPlayer.BLIND_S if hidden else 0.0)


## Ticks the average player takes over the open scan.
func _scan_ticks(w: SimWorld) -> int:
	var truth: Vector3 = ScienceFixture.solution(w, ship)
	var secs: float = ScriptedPlayer.SCAN_READ_S + ScriptedPlayer.CONFIRM_S
	for a: int in 3:
		if w.science.axes[ship] & (1 << a):
			secs += absf(truth[a]) / ScriptedPlayer.TURN_RATE + ScriptedPlayer.SETTLE_S
	return roundi(secs * SimWorld.HZ)
