class_name Factions
extends RefCounted
## The faction ids the scenarios, the director and the encounter builders share (G2, R04-3), so
## no two files spell the same number. The sim itself reads factions only as ids (B5).

## The co-op crew's faction (the first of SessionRules.CREW_FACTIONS).
const CREW: int = 1
## Raiders and drones.
const RAIDER: int = 2
## Freighters and other civilians.
const CIVIL: int = 3
## Debris.
const DEBRIS: int = 4
## The NPC factions: SessionRules.CREW_FACTIONS beyond the first must stay clear of these.
const NPC: Array[int] = [RAIDER, CIVIL, DEBRIS]

## The content key of the raider ship and how far out a raider wave appears (m).
const RAIDER_KEY: StringName = &"m1_raider"
const RAIDER_RANGE_M: float = 9000.0
