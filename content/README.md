# content/

Typed .tres definitions, dialogue JSON, the symbol-font subsets of `fonts/` and the provenance manifest (FT-DAT-001, FT-DAT-012).

Definition classes live in `defs/` (one per file, SI units per field); `tools/check_defs.gd` is the load gate (FT-DAT-002, run by `tools/l0.sh`). The M1 numbers in `ships/`, `weapons/` and `npcs/` are provisional.

Five definitions here serve only tests, and stay so that `check_defs.gd` validates them and the fixtures that scan these folders find them (R03-4): `hazards/p4_dust_cloud.tres` and `hazards/p11_radiation_wave.tres` (the P4 and P11 pair scenarios), and `economy/rep/accept_contract.tres`, `decline.tres` and `complete_mission_fail.tres` (the reputation tests and the escort-contract fixture conversation).
