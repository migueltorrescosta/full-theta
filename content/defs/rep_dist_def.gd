class_name RepDistDef
extends Resource
## The distribution of one reputation interaction (FT-MIS-019, FT-DAT-010, D34): a
## reputation change is drawn from it with the world's seeded "reputation" stream, so
## runs reproduce. `visible` marks where Comms shows the range lo..hi (FT-MIS-020).
## Read-only at runtime (FT-ARC-020).

const KINDS: Array[StringName] = [&"uniform", &"triangular", &"normal_clamped"]

## Unique among distributions (dimensionless id, for example rep.call_bluff).
@export var id: StringName = &""
## uniform on lo..hi; triangular with its peak at mode; normal_clamped with mean mode and
## a standard deviation of a sixth of the range, clamped to lo..hi.
@export var kind: StringName = &"uniform"
## (dimensionless, reputation points) Lowest change.
@export var lo: float = 0.0
## (dimensionless, reputation points) Highest change.
@export var hi: float = 0.0
## (dimensionless, reputation points) The peak (triangular) or mean (normal_clamped).
@export var mode: float = 0.0
## Whether Comms shows lo..hi before the interaction.
@export var visible: bool = false


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if not KINDS.has(kind):
		errors.append("kind: must be one of %s, got %s" % [KINDS, kind])
	if not (is_finite(lo) and is_finite(hi) and lo <= hi):
		errors.append("lo/hi: need finite lo <= hi, got %s, %s" % [lo, hi])
	elif kind != &"uniform":
		DefCheck.in_range(errors, "mode", mode, lo, hi)
	return errors
