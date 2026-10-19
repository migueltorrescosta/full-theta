class_name TestDefs
extends RefCounted
## Loaded M1 definitions for sim tests (tests may load; sim/ never does, FT-ARC-020).


static func corvette() -> ShipDef:
	return load("res://content/ships/m1_corvette.tres") as ShipDef


static func raider() -> ShipDef:
	return load("res://content/ships/m1_raider.tres") as ShipDef


static func raider_enemy() -> EnemyDef:
	return load("res://content/enemies/m1_raider.tres") as EnemyDef
