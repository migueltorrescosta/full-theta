# sim/

Pure simulation: no Node, SceneTree, I/O or load(); depends only on shared/ and content definitions (FT-ARC-010).

- `core/`: `SimWorld` (fixed 60 Hz tick and its phase order in `step()`, seeded streams, command queue and log, events, `state_hash()`), `SimTable` (base of every state container, keyed by ship id and faction), `Kinematics` (site-local 64-bit positions wrapped with period P, minimum-image differences; D104, D124), `Integrator`, `SimCommand` and the `SimCommands` codec, `CommandLog` (replay).
- One folder per area, each a `SimTable` plus a static system and its commands: `flight/` (assist), `power/`, `shields/`, `combat/` (weapons, projectiles, collisions), `damage/`, `knowledge/`, `ai/`, `run/` (outcome, `M1Encounter`, whose rebuild is the run reset, and the server-only reset and abandon commands).
- Ship ids equal the row of every per-ship table; definitions are read, never written (FT-ARC-020).
