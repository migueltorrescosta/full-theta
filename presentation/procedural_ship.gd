## A ship in the approved S8 v2 worn style (D107; FT-AUD-016), loaded from the baked scene
## of its look (D308): content/ships/baked/<look>.scn, made at build time by
## tools/bake_ships.gd with the ambient occlusion already in the vertex colours. Nothing is
## built at run time. Every ship is the same hull; a look has its own seeded panel shades and
## greebles, accent stripe and name decal (D309, content/ships/looks.json). Nose points along
## -Z. Ships of one look share their meshes and materials.
class_name ProceduralShip
extends Node3D

## Hull cross-sections from nose to tail: z, half-width, half-height, centre height.
const SECTIONS: Array[Vector4] = [
	Vector4(-2.7, 0.01, 0.01, -0.04),
	Vector4(-2.55, 0.1, 0.06, -0.03),
	Vector4(-2.2, 0.2, 0.13, -0.01),
	Vector4(-1.6, 0.33, 0.21, 0.02),
	Vector4(-0.8, 0.44, 0.26, 0.04),
	Vector4(0.2, 0.5, 0.28, 0.04),
	Vector4(1.4, 0.5, 0.27, 0.03),
	Vector4(2.1, 0.44, 0.24, 0.02),
	Vector4(2.3, 0.4, 0.21, 0.02),
	Vector4(2.32, 0.3, 0.15, 0.02),
	Vector4(2.34, 0.01, 0.01, 0.02),
]
const BAKED_DIR: String = "res://content/ships/baked/"
## The look of a ship with no look of its own: no decal, the plain violet stripe.
const GENERIC: String = "generic"

## Look -> its baked PackedScene, once loaded.
static var _scenes: Dictionary[String, PackedScene] = {}

## The baked look to show (a name from `look_for`); set before the ship enters the tree, or
## change it with `set_look`.
var look: String = GENERIC


func _ready() -> void:
	add_child(instance(look))


## The look of the ship called `ship_name`: its own when one is baked for the name (the
## names a new ship takes, D284), the generic look otherwise.
static func look_for(ship_name: String) -> String:
	var key: String = ship_name.to_lower()
	if key != "" and key != GENERIC and ResourceLoader.exists(BAKED_DIR + key + ".scn"):
		return key
	return GENERIC


## Whether `look_name`'s baked scene is loaded.
static func is_loaded(look_name: String) -> bool:
	return _scenes.has(look_name)


## The baked scene of `look_name`, loaded on first use.
static func scene(look_name: String) -> PackedScene:
	if not _scenes.has(look_name):
		_scenes[look_name] = load(BAKED_DIR + look_name + ".scn")
	return _scenes[look_name]


## A new copy of the ship of `look_name`, sharing the baked meshes and materials.
static func instance(look_name: String) -> Node3D:
	return scene(look_name).instantiate() as Node3D


## Shows another look.
func set_look(look_name: String) -> void:
	look = look_name
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	add_child(instance(look))
