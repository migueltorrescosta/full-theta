class_name S5HelmState
extends RefCounted
## Helm's flight-control state: mode, throttle setpoint and the latched assist modes.

enum Level { OFF, ROLL, ROLL_AND_PITCH }

## Decoupled mode turns the holds off (FT-SIM-005); assist is on by default (FT-SIM-004).
var decoupled: bool = false
## Forward speed setpoint (m/s) that assist holds; throttle sets speed, not force.
var throttle_setpoint: float = 0.0
## Latched all-stop (FT-SIM-036): runs until the ship is at rest or Helm takes over.
var all_stop: bool = false
var level: Level = Level.OFF
## Index of the selected item in the world's item list.
var selected: int = 0
## Whether hold-to-approach was held on the previous tick (to hand control back).
var approaching: bool = false
