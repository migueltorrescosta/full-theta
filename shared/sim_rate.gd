class_name SimRate
extends RefCounted
## The simulation's tick rate, the one place it is written (G8, R14-4, R12-9). `SimWorld.HZ`
## is this value; clients and the net layer, which may not name `sim/`, read it here.

## Simulation ticks per second.
const HZ: int = 60
