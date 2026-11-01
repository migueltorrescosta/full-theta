class_name RelaunchPolicy
extends RefCounted
## Whether a destroyed or forfeited ship's crew may relaunch, per side (team) of a session
## (#11, owner M4-Q2, 2026-10-28): none, a number of lives, or unlimited. The session's
## SessionRules holds one per team; a relaunch spawns a fresh ship of the same slot at the
## side's start point with a fresh run state (RelaunchShipCommand). Pure value.

## NONE: out until the session ends (D91). LIVES: up to `lives` relaunches. UNLIMITED: always.
enum Kind { NONE, LIVES, UNLIMITED }

## Wire and log names, in Kind order.
const KIND_NAMES: Array[String] = ["none", "lives", "unlimited"]

var kind: Kind = Kind.NONE
## Relaunches allowed with Kind.LIVES (count, at least 1); ignored otherwise.
var lives: int = 0


static func none() -> RelaunchPolicy:
	return RelaunchPolicy.new()


static func of_lives(count: int) -> RelaunchPolicy:
	var p: RelaunchPolicy = RelaunchPolicy.new()
	p.kind = Kind.LIVES
	p.lives = count
	return p


static func unlimited() -> RelaunchPolicy:
	var p: RelaunchPolicy = RelaunchPolicy.new()
	p.kind = Kind.UNLIMITED
	return p


## Whether a ship that has relaunched `used` times may relaunch again.
func allows(used: int) -> bool:
	match kind:
		Kind.UNLIMITED:
			return true
		Kind.LIVES:
			return used < lives
	return false


## Relaunches left after `used`, or -1 for unlimited.
func left(used: int) -> int:
	match kind:
		Kind.UNLIMITED:
			return -1
		Kind.LIVES:
			return maxi(lives - used, 0)
	return 0


func errors() -> Array[String]:
	var out: Array[String] = []
	if kind == Kind.LIVES and lives < 1:
		out.append("relaunch lives must be at least 1, got %d" % lives)
	return out


func to_dict() -> Dictionary:
	return {"kind": KIND_NAMES[kind], "lives": lives}


## The policy a to_dict() names, or null for an unknown kind.
static func from_dict(d: Dictionary) -> RelaunchPolicy:
	var k: int = KIND_NAMES.find(str(d.get("kind", "")))
	if k < 0:
		return null
	var p: RelaunchPolicy = RelaunchPolicy.new()
	p.kind = k as Kind
	p.lives = int(d.get("lives", 0))
	return p
