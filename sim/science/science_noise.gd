class_name ScienceNoise
extends RefCounted
## The server-side scan noise model (FT-SCI-005, D58, P3, P10, P13). Pure: every input
## is a parameter, so the table tests and the UI preview call it the same way.
##
## noise = (base + range_weight * range_term + aspect_weight * aspect_term
##          + health_weight * (1 - sensor_effectiveness))
##         * pip_factor * mode_factor * ping_factor * probe_factor * mark_factor,
## clamped to 0..1. The range term is distance / range_ref (clamped); the aspect term
## is |cos| of the angle between the contact's bow and the line of sight (0 broadside,
## 1 bow-on or stern-on); pip_factor is 1 - pip_gain * (pips - nominal), clamped to
## 0.5..2 (more sensor pips, less noise; P10); mode_factor is active_factor in active
## mode; the ping, probe (P13) and mark (P3) factors apply while their condition holds.
## Occlusion by hazards is a probe/Relay concern (strand B) and not modelled here.


## The noise of a scan, 0..1. `aspect` is the aspect term (0..1) and `sensor_eff` the
## sensors' effectiveness (0..1).
static func compute(
	def: ScienceDef,
	dist: float,
	aspect: float,
	sensor_eff: float,
	pips: int,
	nominal_pips: int,
	is_active: bool,
	pinging: bool,
	probe_covered: bool,
	at_mark: bool
) -> float:
	var raw: float = (
		def.noise_base
		+ def.range_weight * clampf(dist / def.range_ref, 0.0, 1.0)
		+ def.aspect_weight * clampf(aspect, 0.0, 1.0)
		+ def.health_weight * (1.0 - clampf(sensor_eff, 0.0, 1.0))
	)
	raw *= pip_factor(def, pips, nominal_pips)
	if is_active:
		raw *= def.active_factor
	if pinging:
		raw *= def.ping_factor
	if probe_covered:
		raw *= def.probe_factor
	if at_mark:
		raw *= def.mark_factor
	return clampf(raw, 0.0, 1.0)


static func pip_factor(def: ScienceDef, pips: int, nominal_pips: int) -> float:
	return clampf(1.0 - def.pip_gain * float(pips - nominal_pips), 0.5, 2.0)


## Rotation axes the scan needs at this noise: 1 when clean to 3 when noisy
## (FT-SCI-014), at most 3 - pre_aligned_axes when the class was fully scanned this run
## (FT-SCI-015) and `pre_aligned` is set.
static func axes_for(def: ScienceDef, noise: float, pre_aligned: bool) -> int:
	var n: int = 1
	if noise >= def.axes_noise_steps[0]:
		n = 2
	if noise >= def.axes_noise_steps[1]:
		n = 3
	if pre_aligned:
		n = mini(n, 3 - def.pre_aligned_axes)
	return maxi(n, 1)
