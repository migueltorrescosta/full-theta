class_name RelaunchShipCommand
extends ServerCommand
## Puts an eliminated crewed ship back into play (#11, owner M4-Q2, 2026-10-28) when its
## side's RelaunchPolicy (SessionRules.relaunch_for(team)) allows another relaunch: a fresh
## ship of the same slot at the side's start point, its run progress reset (FT-MIS-012),
## its relaunch count up by one, then &"relaunched" (SessionOutcome.EVENT_RELAUNCHED). The
## server sends it when the ship's crew votes for it (NetProtocol.Type.RELAUNCH); logged
## like every SERVER command (FT-ARC-008).
##
## CONTRACT STUB (strand A): refuses every ship until the relaunch count and the start
## points exist.

## The eliminated ship to relaunch.
var ship: int = -1


func kind() -> StringName:
	return &"relaunch_ship"


## Rejects a ship that is not crewed, is still in play, or whose side has no relaunch left.
func apply(_world: SimWorld) -> bool:
	return false
