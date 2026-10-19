class_name SimCommands
extends RefCounted
## Command codec for the command log (FT-ARC-008): kind name to command class.


static func from_dict(d: Dictionary) -> SimCommand:
	var c: SimCommand = make(StringName(d.get("kind", "")))
	if c != null:
		c.set_from_dict(d)
	return c


static func make(kind: StringName) -> SimCommand:
	match kind:
		&"dispatch_repair":
			return DispatchRepairCommand.new()
		&"recall_repair":
			return RecallRepairCommand.new()
		_:
			return null
