class_name S5FixedStep
extends RefCounted
## Fixed-step accumulator (FT-ARC-006): turns variable frame time into whole 60 Hz ticks.

var dt: float = 1.0 / 60.0
## Ticks allowed per frame; a longer stall drops time instead of spiralling.
var max_ticks: int = 8
var _acc: float = 0.0


## Adds frame time and returns how many ticks to run now.
func advance(frame_delta: float) -> int:
	_acc += frame_delta
	var n: int = floori(_acc / dt)
	_acc -= n * dt
	if n > max_ticks:
		n = max_ticks
		_acc = 0.0
	return n


## Fraction of a tick left over, for interpolating visuals.
func alpha() -> float:
	return _acc / dt
