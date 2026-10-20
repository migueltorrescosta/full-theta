class_name StationRegistry
extends RefCounted
## Station id -> the StationPanel class that draws it. Station strands add one line
## each; a station missing here gets PlaceholderPanel (Science and Comms in M1,
## FT-M1-005, and any unknown id).


## A new panel for `station` (not set up yet).
static func make(station: String) -> StationPanel:
	match station:
		"helm":
			return HelmPanel.new()
		"weapons":
			return WeaponsPanel.new()
		"engineering":
			return EngineeringPanel.new()
		"relay":
			return RelayPanel.new()
		"viewer":
			return ViewerPanel.new()
	return PlaceholderPanel.new()
