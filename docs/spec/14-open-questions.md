# 14. Open questions

No open questions from v0.4: the owner answered Q1–Q13 with D76–D89 (`decisions.md`). Q1–Q13 are retired; new questions continue from Q14.

The questions below arose while applying D76–D89. Each has one Recommended option.

### Q14. Normal preset for the shortcuts D84 does not name (D84)

D84 sets Normal for request chips, routes, lanes, hazard countdowns, weak points, track feeds, diagnosed causes and summaries, but not for contract flags on the Weapons reticle (P9), Science icons and the verify chip on dialogue options (P14), or the mission mark icon (P15).

- **A (Recommended):** Mission mark icon on (positional, like routes and lanes); contract flags and Science icons by voice (another station's analysis, like weak points and diagnosed causes).
- B: All three on.
- C: All three by voice.

Affects FT-PAIR-018, §7.2.

### Q15. Does the threat budget follow the preset after toggles are edited? (D81, D84)

Difficulty sizes the director budget and presets the toggles; players may then change single toggles.

- **A (Recommended):** The budget follows the chosen difficulty only; edited toggles change no budget, and the lobby and debrief show the difficulty as "custom" (for example "Hard, custom").
- B: The lobby has two separate settings: threat budget (Easy, Normal, Hard) and shortcut preset.
- C: The budget scales with the number of toggles left on.

Affects FT-MIS-028, FT-PAIR-017.

### Q16. Eliminated crews with no surviving friendly ship (D79)

The default makes eliminated players viewers of a friendly ship's main screen, but in last ship standing, and when a whole team is out, no friendly ship remains.

- **A (Recommended):** They wait in the lobby with a live scoreboard (ships left, objectives) until the session ends; no view that could feed callouts to a surviving ship.
- B: They view any surviving ship's main screen.
- C: They get a full-map spectator view.

Affects FT-MIS-030.

## Resolved (owner, after v0.4 review)

- Q14 → D90: Normal preset has the mission mark icon on; contract flags on Weapons' reticle and Science verify chips go by voice.
- Q15 → D92: editing toggles leaves the threat budget at the chosen difficulty; the preset shows as "<Preset> (custom)". The director is procedural software on the host (no human GM).
- Q16 → D91: eliminated crews with no friendly ship left wait in the lobby with a live scoreboard.
