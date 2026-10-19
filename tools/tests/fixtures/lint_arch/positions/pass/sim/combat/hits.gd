extends RefCounted

## Never read kin.px directly: use Kinematics.relative (FT-SIM-035).
func dx(kin: Kinematics, i: int, j: int) -> float:
	var copy := kin.pxy  # not a column; kin.px would be
	var label := "kin.px[i]"
	return kin.relative(i, j).x + copy.py_ratio + px + label.length()
