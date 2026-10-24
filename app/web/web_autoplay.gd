class_name WebAutoplay
extends Node
## Browser test hooks (?pick=ENTRY&ready=1, JoinHelpers): takes the named station on the
## first crew ship and presses Ready, so tools/l4/web.sh needs no lobby clicks. Does
## nothing without ?pick=, and nothing a player could reach by accident.

var client: NetClient
var crew: CrewState
var entry: String = ""
var press_ready: bool = false
var _asked_pick: bool = false
var _next_ready_ms: int = 0


func _process(_delta: float) -> void:
	if not client.is_welcomed() or client.catalogue.is_empty():
		return
	var ships: Array = client.catalogue.get("ships", [])
	if not _asked_pick and crew.entry == "" and not ships.is_empty():
		_asked_pick = true
		client.pick(int((ships[0] as Dictionary)["id"]), entry)
	elif press_ready and crew.entry == entry and not crew.is_started():
		# Refused (coverage) until the other stations have picked: ask again every 2 s.
		var now: int = Time.get_ticks_msec()
		if now >= _next_ready_ms:
			_next_ready_ms = now + 2000
			client.set_ready(true)
