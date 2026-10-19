class_name ShipIntents
extends RefCounted
## What a station sends: the one seam between the station UI and NetClient. Panels call
## these instead of the client, so scene tests swap in a recording fake (any object with
## the same methods) and no panel needs a server.
## Every method is called by name, so a fake needs only the methods a test uses.

## A NetClient, or a test fake with the same methods; null drops everything.
var client: Object = null


func _init(p_client: Object = null) -> void:
	client = p_client


## Sends a crew command ({"kind": ..., fields}); returns its seq, or -1 without a client.
func command(cmd: Dictionary) -> int:
	return int(_call(&"command", [cmd], -1))


## Alert level 0 Normal, 1 Yellow, 2 Red (FT-STN-008).
func set_alert(level: int) -> void:
	_call(&"set_alert", [level])


## slot -1 takes the first free one; contact >= 0 attaches the mark, else it is free at
## site + pos (FT-SPA-012, FT-SPA-014).
func place_mark(slot: int, mark_name: String, contact: int, site: int, pos: Vector3) -> void:
	_call(&"place_mark", [slot, mark_name, contact, site, pos])


func move_mark(slot: int, contact: int, site: int, pos: Vector3) -> void:
	_call(&"move_mark", [slot, contact, site, pos])


func rename_mark(slot: int, mark_name: String) -> void:
	_call(&"rename_mark", [slot, mark_name])


func delete_mark(slot: int) -> void:
	_call(&"delete_mark", [slot])


## kind "contact" | "mark" | "site" | "point" (FT-SPA-016).
func ping(kind: String, id: int, site: int, pos: Vector3) -> void:
	_call(&"ping", [kind, id, site, pos])


func claim(item: String) -> void:
	_call(&"claim", [item])


func release_claim(item: String) -> void:
	_call(&"release_claim", [item])


func pick(ship: int, entry: String) -> void:
	_call(&"pick", [ship, entry])


func release_pick() -> void:
	_call(&"release_pick", [])


## Start (D129).
func start() -> void:
	_call(&"set_ready", [true])


func vote_abandon(ship: int, vote: bool) -> void:
	_call(&"vote_abandon", [ship, vote])


func abandon(ship: int) -> void:
	_call(&"abandon", [ship])


func takeover(ship: int, entry: String) -> void:
	_call(&"takeover", [ship, entry])


func _call(method: StringName, args: Array, fallback: Variant = null) -> Variant:
	if client == null or not client.has_method(method):
		return fallback
	return client.callv(method, args)
