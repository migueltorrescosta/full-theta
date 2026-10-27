class_name RelaunchShipCommand
extends ServerCommand
## Puts an eliminated crewed ship back into play (#11, owner M4-Q2, 2026-10-28) when its
## side's RelaunchPolicy (SessionRules.relaunch_for(team)) allows another relaunch: a fresh
## ship of the same slot at the side's start point, its run progress reset (FT-MIS-011),
## its relaunch count up by one, then &"relaunched" (SessionOutcome.EVENT_RELAUNCHED). The
## server sends it when the ship's crew votes for it (NetProtocol.Type.RELAUNCH); logged
## like every SERVER command (FT-ARC-008). The fresh ship stands where the slot started
## (SimWorld.ship_starts) with the run's starting purse; its relaunch and kill counts carry
## over (RunTable.reset_ship).

## The eliminated ship to relaunch.
var ship: int = -1


func kind() -> StringName:
	return &"relaunch_ship"


## Rejects a ship that is not crewed, is still in play, or whose side has no relaunch left.
func apply(world: SimWorld) -> bool:
	if ship < 0 or ship >= world.ship_count() or world.ai.is_enabled(ship):
		return false
	if world.run.status[ship] == RunTable.Status.IN_PLAY:
		return false
	var policy: RelaunchPolicy = world.rules.relaunch_for(world.team_of(ship))
	var used: int = world.run.relaunches[ship]
	if not policy.allows(used):
		return false
	var at: Vector3 = world.ship_starts.get(ship, Vector3.ZERO)
	world.reset_ship(ship, at.x, at.y, at.z)
	world.run.relaunches[ship] = used + 1
	if world.run_def != null:
		Economy.add_credits(world, ship, world.run_def.start_credits)
	world.emit(SessionOutcome.EVENT_RELAUNCHED, ship, -1, policy.left(used + 1))
	return true
