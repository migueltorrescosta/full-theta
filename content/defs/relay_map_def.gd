class_name RelayMapDef
extends Resource
## What Relay's map shows of the director's plans (gp-16, amends D250): the site of an
## encounter still waiting for the ship shows as a dashed "?" this long after the encounter
## opened, until it starts or ends. Comms' INFO card names it first. Read-only at runtime
## (FT-ARC-020); the SITES section reads it (SitesSection).

@export var id: StringName = &""
## Seconds from an encounter opening until its site's "?" shows on Relay's map (s).
@export var site_marker_delay: float = 30.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if site_marker_delay < 0.0:
		errors.append("site_marker_delay must be at least 0, got %s" % site_marker_delay)
	return errors
