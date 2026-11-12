extends RefCounted


## Never read kin.pos_x directly: use Kinematics.relative (FT-SIM-035).
func dx(kin: Kinematics, i: int, j: int) -> float:
	var copy := kin.pos_xy  # not a column; kin.pos_x would be
	var label := "kin.pos_x[i]"
	return kin.relative(i, j).x + copy.pos_y_ratio + pos_x + label.length()


# Other tables' point columns are read directly (D401).
func site_x(sites: SiteTable, s: int) -> float:
	return sites.pos_x[s]
