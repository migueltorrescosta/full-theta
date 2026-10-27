class_name SimCommands
extends RefCounted
## Command codec for the command log (FT-ARC-008): kind name to command class. Adding a
## command class is one line in the list _classes is built from.

## Kind name to command class, built from the list of classes.
static var _classes: Dictionary[StringName, GDScript] = _by_kind(
	[
		HelmInputCommand,
		DecoupledCommand,
		AllStopCommand,
		AlignCommand,
		SelectTargetCommand,
		DispatchRepairCommand,
		RecallRepairCommand,
		PickFaultCauseCommand,
		HardenCommand,
		SetPipsCommand,
		BoostCommand,
		SetShieldCommand,
		SetShieldFocusCommand,
		AimMountCommand,
		FireCommand,
		FireGuidedCommand,
		SetAmmoTypeCommand,
		ResetShipCommand,
		AbandonShipCommand,
		ScienceScanCommand,
		ScienceScanSubmitCommand,
		ScienceHackCommand,
		ScienceHackMoveCommand,
		ScienceCancelCommand,
		ScienceSelfScanCommand,
		ScienceSensorModeCommand,
		SciencePingCommand,
		ScienceMarkCommand,
		ScienceSelectCommand,
		LaunchProbeCommand,
		FabricateProbeCommand,
		FlagLanesCommand,
		SayCommand,
		HailCommand,
		AnswerHailCommand,
		ReplyCommand,
		AcceptCardCommand,
		DeclineCardCommand,
		TradeCommand,
		BuyModuleCommand,
		SellModuleCommand,
		PostCardCommand,
		SetContractFlagCommand,
		CardResultCommand,
		MarkMissionCommand,
		SpawnShipCommand,
		OpenSiteCommand,
		SetFlagCommand,
		SetRelationCommand,
		BeginEncounterCommand,
		EndEncounterCommand,
		AbandonRunCommand,
		CloseRunCommand,
		TrainingNextCommand,
		JumpCommand,
		DockCommand,
		UndockCommand,
	]
)


static func from_dict(d: Dictionary) -> SimCommand:
	var c: SimCommand = make(StringName(d.get("kind", "")))
	if c != null:
		c.set_from_dict(d)
	return c


static func make(kind: StringName) -> SimCommand:
	var cls: GDScript = _classes.get(kind)
	return cls.new() if cls != null else null


static func _by_kind(classes: Array[GDScript]) -> Dictionary[StringName, GDScript]:
	var out: Dictionary[StringName, GDScript] = {}
	for cls: GDScript in classes:
		out[(cls.new() as SimCommand).kind()] = cls
	return out
