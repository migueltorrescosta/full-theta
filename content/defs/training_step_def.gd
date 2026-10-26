class_name TrainingStepDef
extends Resource
## One step of the Shakedown (FT-MIS-039, D235): what one station is taught next, and how
## the step ends. A step on a control that sends a sim command ends when that command is
## accepted from the station (COMMAND, `command` names it); a step on a control with no
## sim command, or one the training world cannot trigger, ends when the station presses
## Next (NEXT). A pair step (`partner` set) ends when both of its stations press Next.
## Read-only at runtime (FT-ARC-020).

enum Kind { COMMAND, NEXT }

## The crew station (or Captain seat) the step is for; a pair step's first station.
@export var station: StringName = &""
## The IntentTable id the step teaches, or pair_pN for a pair step.
@export var intent: StringName = &""
## A pair step's second station, else empty.
@export var partner: StringName = &""
@export var kind: Kind = Kind.NEXT
## COMMAND steps: the SimCommand kind, or kind:detail where the kind alone is too coarse
## (helm_input:face, helm_input:approach, helm_input:throttle, ...), as ScenarioApi's
## commands_this_tick reports it.
@export var command: StringName = &""
## Dialogue line id (content/dialogue/shakedown.json): the spoken action plus the binding.
@export var line: String = ""
## UI string key of the worked example (content/i18n/strings.json), short and imperative.
@export var example: String = ""


func is_pair() -> bool:
	return partner != &""


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "station", station)
	DefCheck.id(errors, "intent", intent)
	if kind == Kind.COMMAND and command == &"":
		errors.append("command: a COMMAND step needs the command kind")
	if kind == Kind.NEXT and command != &"":
		errors.append("command: a NEXT step has none, got %s" % command)
	if is_pair() and kind != Kind.NEXT:
		errors.append("kind: a pair step ends on Next")
	if not line.begins_with("shakedown."):
		errors.append("line: must be a shakedown.* dialogue line, got %s" % line)
	if example == "":
		errors.append("example: must not be empty")
	return errors
