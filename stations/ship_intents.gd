# gdlint: disable=max-public-methods
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


## Relay (strand B of #9): send the mark in `slot` to an allied ship's Relay (FT-RLY-008);
## accept the inbox item `id`, replacing `slot` when all 8 marks are used (slot -1: a free
## one), or decline it (FT-RLY-009, FT-SPA-022).
func send_mark(slot: int, to_ship: int) -> void:
	_call(&"send_mark", [slot, to_ship])


func accept_mark(id: int, slot: int) -> void:
	_call(&"accept_mark", [id, slot])


func decline_mark(id: int) -> void:
	_call(&"decline_mark", [id])


## Routes and hazard zones (FT-RLY-005, FT-SPA-028): a waypoint on route `route`, clear
## it, a hazard of `radius_m` at a point, delete the zone `id`.
func route_add(route: int, site: int, pos: Vector3) -> void:
	_call(&"route_add", [route, site, pos])


func route_clear(route: int) -> void:
	_call(&"route_clear", [route])


func hazard_add(radius_m: float, site: int, pos: Vector3) -> void:
	_call(&"hazard_add", [radius_m, site, pos])


func hazard_delete(id: int) -> void:
	_call(&"hazard_delete", [id])


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


## "Run again" after the outcome (D178); the host's vote resets at once.
func run_again(ship: int, vote: bool) -> void:
	_call(&"run_again", [ship, vote])


func takeover(ship: int, entry: String) -> void:
	_call(&"takeover", [ship, entry])


func _call(method: StringName, args: Array, fallback: Variant = null) -> Variant:
	if client == null or not client.has_method(method):
		return fallback
	return client.callv(method, args)
