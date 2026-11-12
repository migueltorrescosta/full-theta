class_name RelaunchShipCommand
extends ServerCommand
## Puts an eliminated crewed ship back into play (#11, owner M4-Q2, 2026-10-28) when its
## faction's RelaunchPolicy (GameRules.relaunch_for(faction)) allows another relaunch: a fresh
## ship of the same slot at the slot's start point, its run progress reset (FT-MIS-011),
## its relaunch count up by one, then &"relaunched" (GameOutcome.EVENT_RELAUNCHED). The
## server sends it when the ship's crew votes for it (NetProtocol.Type.RELAUNCH); logged
## like every SERVER command (FT-ARC-008). The fresh ship stands where the slot started
## (SimWorld.ship_starts) with the run's starting purse; its relaunch and kill counts carry
## over (ShipStateTable.reset_ship).

## The eliminated ship to relaunch.
var ship: int = -1


func kind() -> StringName:
	return &"relaunch_ship"


## Rejects a ship that is not crewed, is still in play, or whose faction has no relaunch left.
func apply(world: SimWorld) -> bool:
	if not world.has_ship(ship) or not world.is_crew(ship):
		return false
	if world.ships.status[ship] == ShipStateTable.Status.IN_PLAY:
		return false
	var policy: RelaunchPolicy = world.rules.relaunch_for(world.faction_of(ship))
	var used: int = world.ships.relaunches[ship]
	if not policy.allows(used):
		return false
	world.reset_ship(ship, world.ship_starts.get(ship, CubePoint.make()))
	world.ships.relaunches[ship] = used + 1
	if world.run_def != null:
		Economy.add_credits(world, ship, world.run_def.start_credits)
	world.emit(GameOutcome.EVENT_RELAUNCHED, ship, -1, policy.left(used + 1))
	return true
