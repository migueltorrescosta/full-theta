class_name SimCommands
extends RefCounted
## Command codec for the command log (FT-ARC-008): kind name to command class. Each area
## adds one line per command class here.

static var _classes: Dictionary[StringName, GDScript] = {
	&"helm_input": HelmInputCommand,
	&"helm_decoupled": DecoupledCommand,
	&"helm_all_stop": AllStopCommand,
	&"helm_level": LevelCommand,
	&"helm_select_target": SelectTargetCommand,
	&"dispatch_repair": DispatchRepairCommand,
	&"recall_repair": RecallRepairCommand,
}


static func from_dict(d: Dictionary) -> SimCommand:
	var c: SimCommand = make(StringName(d.get("kind", "")))
	if c != null:
		c.set_from_dict(d)
	return c


static func make(kind: StringName) -> SimCommand:
	var cls: GDScript = _classes.get(kind)
	return cls.new() if cls != null else null


static func kinds() -> Array[StringName]:
	return _classes.keys()
