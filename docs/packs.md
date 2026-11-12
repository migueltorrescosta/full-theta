# Content packs

A content pack is one JSON file that adds NPC ships and encounters to the director's run (FT-DAT-015, D472). Packs are data only: the game reads `*.json` files and nothing else, so a pack can't run code. A pack never replaces built-in content, and only the host needs it.

## Use a pack

**Start the host with `--packs` and the folder that holds the pack files.**

```bash
build/linux/full-theta.x86_64 -- --packs /home/me/full-theta-packs
```

The folder path must be absolute. The server prints `packs: <id> (<file>)` for each pack it loaded. If a pack has an error, the server prints each one as `<file>: <field>: <problem>` and doesn't start (FT-DAT-016, D473). Fix the file and start again.

Players who join need nothing: the host runs the NPCs.

> **Good to know:** starting a server with `--packs` is also how you check a pack you wrote.

## Write a pack

**Copy the example and change its numbers.** The example is `tests/fixtures/packs/heavy_raiders.json`, which the tests load.

The top level holds:

| Key | Value |
|---|---|
| `format` | `1` |
| `id` | lower case letters, digits and `_`, starting with a letter, up to 32 characters; unique among the loaded packs |
| `name`, `author`, `licence` | optional text, up to 40 characters |
| `ships` | a list of ships (optional) |
| `encounters` | a list of encounters (optional); a pack needs at least one ship or encounter |

A ship copies a built-in NPC and changes some of its numbers. Its key in the game is `<pack id>.<ship id>`.

| Key | Value |
|---|---|
| `id` | as the pack id |
| `base` | a built-in NPC: `m1_raider`, `drone`, `debris` or `stranded_freighter` |
| `name` | optional display name |
| `hull_max`, `sensor_range`, `identify_range` | optional numbers for the ship (SI units, as in `ShipDef`) |
| `engage_range_min`, `engage_range_max`, `retreat_hull_fraction`, `fire_cone` | optional numbers for its behaviour (as in `NpcDef`) |

An encounter is a wave of one NPC type. The NPCs arrive one after another, hail and taunt the crew, and the encounter is won once every NPC is destroyed or gone. When its time limit passes, it ends partial. The director picks it like any built-in encounter, by its threat cost (`PackWave` in `scenarios/pack_wave.gd`).

| Key | Value |
|---|---|
| `id` | as the pack id |
| `ship` | one of this pack's ship ids, or a built-in NPC |
| `name` | optional name the NPCs speak as |
| `count` | whole number of NPCs at normal strength, 1 to 6 |
| `threat_cost` | whole number the director charges, 1 to 9 |
| `second_after` | seconds until the second NPC arrives, 0 to 600 |
| `next_every` | seconds between later arrivals, 1 to 600 |
| `taunt_after` | seconds until the taunt, 0 to 600 |
| `time_limit` | seconds until the encounter ends partial, 30 to 1800 |

Missing encounter numbers take the defaults in `PackWave.DEFAULTS`. Any other key is an error, so a typo never goes unnoticed. The checks are `ContentPacks` in `app/content_packs.gd`.
