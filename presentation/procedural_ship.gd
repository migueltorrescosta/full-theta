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
## The greebles, vents and antenna are separate meshes in this group; they show within
## DETAIL_RANGE (m, for an unscaled ship) and drop out beyond it (E1).
const DETAIL_GROUP: StringName = &"ship_detail"
const DETAIL_RANGE: float = 40.0

## Look -> its baked PackedScene, once loaded.
static var _scenes: Dictionary[String, PackedScene] = {}
## The Low Graphics tier (E2): ships are drawn with flat materials, without the triplanar
## plating and normal maps (the baked occlusion stays). Set from the client settings; a
## ship built before a change is rebuilt by `rebuild_if_stale`.
static var low_graphics: bool = false
## Baked material -> its flat Low Graphics copy.
static var _flat: Dictionary[StandardMaterial3D, StandardMaterial3D] = {}

## The baked look to show (a name from `look_for`); set before the ship enters the tree, or
## change it with `set_look`.
var look: String = GENERIC
## The factor of the model's scale, so the detail range follows it (SpaceScene.ship_scale).
var detail_scale: float = 1.0
var _built_low: bool = false
var _model: Node3D = null


func _ready() -> void:
	_add_model()


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
	var ship: Node3D = scene(look_name).instantiate() as Node3D
	if low_graphics:
		for body: Node in ship.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = body as MeshInstance3D
			mesh.material_override = flat_material(mesh.material_override as StandardMaterial3D)
	return ship


## `baked` without its textures, triplanar mapping and normal map (E2). The baked meshes
## carry no texture coordinates worth sampling, so the plain colour and the vertex
## occlusion are what is left; the glass and glow materials are as baked.
static func flat_material(baked: StandardMaterial3D) -> StandardMaterial3D:
	if not baked.uv1_triplanar:
		return baked
	if not _flat.has(baked):
		var m: StandardMaterial3D = baked.duplicate() as StandardMaterial3D
		m.uv1_triplanar = false
		m.normal_enabled = false
		m.normal_texture = null
		m.albedo_texture = null
		m.roughness_texture = null
		_flat[baked] = m
	return _flat[baked]


## Shows another look.
func set_look(look_name: String) -> void:
	look = look_name
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_add_model()


## Whether the model was built under another Low Graphics setting than the current one.
func is_stale() -> bool:
	return _built_low != low_graphics


## Sets the scale the detail range follows (a model drawn at 9x keeps its greebles 9x as far).
func set_detail_scale(factor: float) -> void:
	detail_scale = factor
	if _model != null:
		_range_details(_model)


func _add_model() -> void:
	_model = instance(look)
	_built_low = low_graphics
	add_child(_model)
	_range_details(_model)


func _range_details(model: Node3D) -> void:
	for c: Node in model.get_children():
		if c.is_in_group(DETAIL_GROUP):
			(c as MeshInstance3D).visibility_range_end = DETAIL_RANGE * detail_scale
