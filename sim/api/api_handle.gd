class_name ApiHandle
extends RefCounted
## What a Scenario API write that creates something returns (Q24, owner 2026-10-26): a ship,
## a card, an encounter or a site. The id is not known until the command applies on the next
## tick, and an earlier command of the same tick (a crew hail adding a card, a rejected
## begin) can change it, so a scenario never predicts one: it keeps the handle and asks it
## after the tick. A handle holds the queued command, nothing of the world.

var _cmd: SimCommand
var _known: int = -1


## A handle on a write queued as `cmd`, or, when `known` is 0 or more, one already resolved
## (opening a site that is open queues nothing).
func _init(cmd: SimCommand = null, known: int = -1) -> void:
	_cmd = cmd
	_known = known


## The id of the created thing, or -1 while the command is queued or after it was rejected.
func id() -> int:
	if _known >= 0:
		return _known
	return _cmd.result_id if _cmd != null and _cmd.tick >= 0 and _cmd.accepted else -1


## Whether the command has not been applied yet.
func pending() -> bool:
	return _known < 0 and (_cmd == null or _cmd.tick < 0)


## Whether the command was applied and refused, or dropped (its ship was destroyed or reset).
func rejected() -> bool:
	return _known < 0 and _cmd != null and _cmd.tick >= 0 and not _cmd.accepted
