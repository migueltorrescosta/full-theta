class_name SoundPlayers
extends RefCounted
## The setup AlertTones and GameSounds share: a bus sent to Master, and one
## AudioStreamPlayer per sound on it.


## Creates the bus `bus` when the layout lacks it (sent to Master, never to Voice or Music).
static func ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, "Master")


## Adds a player named after each of `names` to `parent` on `bus`, loading
## `<sounds_dir>/<name><ext>` when `sounds_dir` is set; returns {name: player}.
static func add_players(
	parent: Node, names: Array[StringName], bus: String, sounds_dir: String, ext: String
) -> Dictionary:
	var players: Dictionary = {}
	for n: StringName in names:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = String(n)
		p.bus = bus
		if sounds_dir != "":
			p.stream = load(sounds_dir.path_join(String(n) + ext)) as AudioStream
		parent.add_child(p)
		players[n] = p
	return players
