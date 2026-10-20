class_name S5Item
extends RefCounted
## A selectable thing: a contact (callsign) or a mark (spec §6.1). Site-local position
## and velocity (FT-SIM-035).

enum Kind { CONTACT, MARK }

var name: String = ""
var kind: Kind = Kind.CONTACT
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO


static func make(item_name: String, item_kind: Kind, pos: Vector3) -> S5Item:
	var it: S5Item = S5Item.new()
	it.name = item_name
	it.kind = item_kind
	it.position = pos
	return it
