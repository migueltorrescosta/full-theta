class_name StationRegistry
extends RefCounted
## Station id -> the StationPanel script that draws it. Station strands add one line
## each; a station missing here gets PlaceholderPanel (Comms in M1,
## FT-M1-005, Comms; and any unknown id). Paths, loaded on first use, not class names: naming
## the panel classes here would load every station (and its art) whenever the shell
## loads, which costs a client over a second of start-up on two busy cores.

const PANELS: Dictionary = {
	"helm": "res://stations/helm/helm_panel.gd",
	"weapons": "res://stations/weapons/weapons_panel.gd",
	"engineering": "res://stations/engineering/engineering_panel.gd",
	"relay": "res://stations/relay/relay_panel.gd",
	"science": "res://stations/science/science_panel.gd",
	"viewer": "res://stations/viewer/viewer_panel.gd",
}


## A new panel for `station` (not set up yet).
static func make(station: String) -> StationPanel:
	if PANELS.has(station):
		var script: Script = load(PANELS[station])
		if script != null:
			var panel: Variant = script.new()
			if panel is StationPanel:
				return panel
			push_error("%s is not a StationPanel" % PANELS[station])
	return PlaceholderPanel.new()
