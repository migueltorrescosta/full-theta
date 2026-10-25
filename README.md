# Full Theta

A cooperative 3D spaceship bridge simulator for players in the same room, loosely inspired by [EmptyEpsilon](https://github.com/daid/EmptyEpsilon). Each player runs one or more stations (Helm, Weapons, Engineering, Science, Relay, Comms, and an optional Captain seat) aboard a shared ship, over LAN, against one authoritative simulation. Flight is full 3D Newtonian, the look is colourful retro sci-fi, and runs last 20 to 40 minutes. Up to six ships can play together in co-op or PvP.

Status: milestone 1 playable ([docs/launch.md](docs/launch.md)).

## Documentation

- [Specification v0.5](docs/spec/README.md): requirements with stable `FT-…` IDs.
- [Launching](docs/launch.md): host, join, dedicated server and rejoin.
- [Callout card](docs/callout-card.md): one printed page of crew callouts (clock, height, marks, pairs).
- [Decision log](docs/decisions.md): every owner decision (D1–D184) that the spec cites; the plan review behind D95–D102 is in [docs/research/plan-review](docs/research/plan-review/README.md).
- [Task breakdown](docs/plan/task-breakdown.md): the fine-grained implementation DAG behind the GitHub issues.
- Research: [EmptyEpsilon comparison](docs/research/emptyepsilon.md), [technology](docs/research/tech.md), [station UI](docs/research/station-ui.md), [cooperation pairs and joint views](docs/research/pairs-and-combos.md).

## Licence

GPL-3.0. See [LICENSE](LICENSE). Full Theta reuses no EmptyEpsilon code or assets, only ideas; see [licensing and provenance](docs/spec/13-licensing-and-provenance.md).
