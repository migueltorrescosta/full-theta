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
func place_mark(slot: int, mark_name: String, contact: int, pos: Vector3) -> void:
	_call(&"place_mark", [slot, mark_name, contact, pos])


func move_mark(slot: int, contact: int, pos: Vector3) -> void:
	_call(&"move_mark", [slot, contact, pos])


func rename_mark(slot: int, mark_name: String) -> void:
	_call(&"rename_mark", [slot, mark_name])


func delete_mark(slot: int) -> void:
	_call(&"delete_mark", [slot])


## The main screen's view, a MainScreen.View: the Captain, or Relay without a Captain.
func set_main_view(view: int) -> void:
	_call(&"set_main_view", [view])


## kind "contact" | "mark" | "card" | "site" | "point" (FT-SPA-016, FT-CPT-005).
func ping(kind: String, id: int, pos: Vector3) -> void:
	_call(&"ping", [kind, id, pos])


## Relay: send the mark in `slot` to an allied ship's Relay (FT-RLY-008);
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
func route_add(route: int, pos: Vector3) -> void:
	_call(&"route_add", [route, pos])


func route_clear(route: int) -> void:
	_call(&"route_clear", [route])


func hazard_add(radius_m: float, pos: Vector3) -> void:
	_call(&"hazard_add", [radius_m, pos])


func hazard_delete(id: int) -> void:
	_call(&"hazard_delete", [id])


## The host sets the session's data-shortcut toggles in the lobby (a DataToggles
## code); a station sends a request chip (id from content/chips/chips.tres, arg a mount index
## or contact id) or answers one it received.
func set_toggles(code: String) -> void:
	_call(&"set_toggles", [code])


func send_chip(chip: String, arg: int = -1) -> void:
	_call(&"send_chip", [chip, arg])


func answer_chip(id: int, accept: bool) -> void:
	_call(&"answer_chip", [id, accept])


## (D210) Shares a data shortcut from the source station (a toggle id).
func share(feature: String) -> void:
	_call(&"share", [feature])


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


## The host pauses or resumes the universe (FT-MIS-040).
func host_pause(on: bool) -> void:
	_call(&"host_pause", [on])


## "Run again" after the outcome (D178); the host's vote resets at once.
func run_again(ship: int, vote: bool) -> void:
	_call(&"run_again", [ship, vote])


func takeover(ship: int, entry: String) -> void:
	_call(&"takeover", [ship, entry])


## Multi-ship lobby and PvP (#11): any player adds a ship (M4-Q3); a crew puts its ship on
## team 0 or 1 (M4-Q6); the host sets the mode, the team win rule and the holdout lives
## (-1 the mode's default); an eliminated crew votes to relaunch (M4-Q2).
func add_ship(ship_name: String) -> void:
	_call(&"add_ship", [ship_name])


func set_team(ship: int, team: int) -> void:
	_call(&"set_team", [ship, team])


func set_mode(mode: String, team_win: String, lives: int = -1) -> void:
	_call(&"set_mode", [mode, team_win, lives])


func vote_relaunch(ship: int, vote: bool) -> void:
	_call(&"vote_relaunch", [ship, vote])


func _call(method: StringName, args: Array, fallback: Variant = null) -> Variant:
	if client == null or not client.has_method(method):
		return fallback
	return client.callv(method, args)
