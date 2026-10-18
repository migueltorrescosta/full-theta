# 10. Content and data formats

| Content | Format | Validation | Decision |
|---|---|---|---|
| Ships, weapons, mounts, subsystems, upgrades, enemies | Typed `Resource` classes saved as text `.tres` | Headless Godot gate loads every file and checks types, ranges and references | D65 |
| Dialogue and spoken lines | JSON + JSON Schema, one line id per spoken line, text per language | Schema check; read by the TTS prerenderer and translators | D65 |
| Scenarios and mission components | Typed GDScript classes extending a restricted Scenario API, plus declared metadata for the director | Lint gate forbids access to simulation internals | D64 |
| Reputation and other random outcomes | Distributions in data (per interaction type) | Gate checks parameters | D34 |
| Art and sound | Procedural/primitive meshes, CC0 packs (Kenney, Quaternius), CC0 sounds | Provenance manifest entry per file | D63 |
| Localisation | Per-language string tables keyed by the same line ids as TTS | Missing-key check per language | D40 |

Scenario metadata (declared, not computed): id, tags, threat cost, duration estimate, required stations or pairs exercised, branches and their outcomes. The director reads only metadata and the Scenario API.

## 10.1 Requirements

- **FT-DAT-001** Ship, weapon, mount, subsystem, upgrade and enemy definitions shall be typed Resources stored as text `.tres`. (D65)
- **FT-DAT-002** A headless Godot gate shall load every definition and fail on type, range or missing-reference errors, naming file and field. (D65)
- **FT-DAT-003** Dialogue shall be JSON validated against a JSON Schema. (D65)
- **FT-DAT-004** Every spoken line shall have a stable line id shared by subtitles, translations and TTS. (D65, D38)
- **FT-DAT-005** The TTS prerenderer shall read dialogue only from the dialogue JSON. (D65)
- **FT-DAT-006** Scenarios shall be typed GDScript classes extending the Scenario API. (D64)
- **FT-DAT-007** A lint gate shall fail any scenario that references simulation internals outside the Scenario API. (D64)
- **FT-DAT-008** Each scenario shall declare metadata (id, tags, threat cost, duration estimate, branches) for the director. (D64)
- **FT-DAT-009** The Scenario API shall expose only visible world actions (spawn at range, offer, message, set flag, end encounter) and observable queries. (D64, v0.3 §5)
- **FT-DAT-010** Random-outcome distributions shall live in data, not code. (D34)
- **FT-DAT-011** Every translatable string shall exist for each launch language, enforced by a gate. (D40)
- **FT-DAT-012** No EE code, scripts, text, data or assets shall enter the repository. (D2 note, D62)
- **FT-DAT-013** All definitions shall use SI units. (v0.3 §3)
- **FT-DAT-014** Ship definitions shall declare module slots, and each module definition shall declare its slot type and stat trade-offs. (D65, D86)
