class_name PairHarness
extends RefCounted
## Pair test harness (T039, R13, FT-PAIR-015): runs one scripted scenario twice, with a
## co-op script and a solo script, and compares their metrics. A scenario is four
## Callables:
## - build() -> SimWorld: a fresh seeded world (each run builds its own, so the two runs
##   share nothing and every run is deterministic);
## - environment(world): what isn't the crew (scripted enemy fire, events), the same in
##   both variants; it may be a no-op;
## - done(world) -> bool: the completion predicate;
## - measure(world) -> Dictionary: metric name -> float, read when the run ends.
## A crew script is a Callable(world) called every tick before world.step(); like a
## station, it only submits commands. A run ends when done() holds or at tick_limit.

## Metric direction for check().
enum Better { LOWER, HIGHER }


## One finished run.
class Run:
	extends RefCounted
	var completed: bool = false
	## Ticks run (count).
	var ticks: int = 0
	## Metric name -> value, from measure() at the end of the run.
	var metrics: Dictionary = {}
	## World state hash at the end, for determinism checks.
	var state_hash: String = ""


var _build: Callable
var _environment: Callable
var _done: Callable
var _measure: Callable
var _tick_limit: int


func _init(
	build: Callable, environment: Callable, done: Callable, measure: Callable, tick_limit: int
) -> void:
	_build = build
	_environment = environment
	_done = done
	_measure = measure
	_tick_limit = tick_limit


## Runs the scenario with one crew script.
func run(crew: Callable) -> Run:
	var world: SimWorld = _build.call()
	var out: Run = Run.new()
	while world.tick < _tick_limit:
		if _done.call(world):
			out.completed = true
			break
		_environment.call(world)
		crew.call(world)
		world.step()
	out.completed = out.completed or _done.call(world)
	out.ticks = world.tick
	out.metrics = _measure.call(world)
	out.state_hash = world.state_hash()
	return out


## Runs both variants: {"coop": Run, "solo": Run}.
func compare(coop: Callable, solo: Callable) -> Dictionary[String, Run]:
	return {"coop": run(coop), "solo": run(solo)}


## Gain of co-op over solo on one metric (dimensionless): how many times better co-op
## is, minus 1, so 0.25 reads "25 % better": solo / coop - 1 when lower is better (25 %
## faster, or a quarter of the damage would be 3), coop / solo - 1 when higher is. The
## same ratio both ways keeps "beats by 25 %" symmetric (provisional, T039 question).
## Metrics are >= 0; a zero denominator gives INF when the numerator is positive.
static func gain(coop: float, solo: float, better: Better) -> float:
	var num: float = solo if better == Better.LOWER else coop
	var den: float = coop if better == Better.LOWER else solo
	if den == 0.0:
		return INF if num > 0.0 else 0.0
	return num / den - 1.0


## Failure messages for "co-op beats solo by at least min_gain on each listed metric
## and both variants complete" (FT-PAIR-004, FT-PAIR-015); empty when it holds. metrics:
## name -> Better.
static func check(
	runs: Dictionary[String, Run], metrics: Dictionary, min_gain: float
) -> Array[String]:
	var out: Array[String] = []
	for variant: String in ["coop", "solo"]:
		var r: Run = runs[variant]
		if not r.completed:
			out.append("%s did not complete within %d ticks" % [variant, r.ticks])
	for name: String in metrics:
		var c: float = runs.coop.metrics.get(name, NAN)
		var s: float = runs.solo.metrics.get(name, NAN)
		var g: float = gain(c, s, metrics[name])
		if not g >= min_gain:
			out.append(
				(
					"%s (%s is better): co-op %.3f vs solo %.3f, gain %.1f %% < %.1f %%"
					% [
						name,
						"lower" if metrics[name] == Better.LOWER else "higher",
						c,
						s,
						g * 100.0,
						min_gain * 100.0
					]
				)
			)
	return out


## One line per variant with its metrics, for test output and reports.
static func summary(runs: Dictionary[String, Run]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for variant: String in runs:
		var r: Run = runs[variant]
		lines.append("%s: completed %s, %d ticks, %s" % [variant, r.completed, r.ticks, r.metrics])
	return "\n".join(lines)
