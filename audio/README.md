# audio/

Voice system (E10, spec §9): what the client plays, and the contracts with the host's synthesis service in `net/voice/`. Alert tones (FT-AUD-009) are #7's and use their own bus.

## Data

| File | What | Gate |
|---|---|---|
| `content/dialogue/<group>.json` | Spoken lines: stable id, role, priority, max age, coalescing key, resume flag, slots, text per language | `dialogue.schema.json` plus `tools/check_dialogue.py` (FT-DAT-003, FT-DAT-004, FT-DAT-011) |
| `content/dialogue/numbers.json` | Number fragments per language (keys composed by `NumberWords`) | `numbers.schema.json` |
| `content/i18n/strings.json` | UI strings per language | `tools/check_dialogue.py` |
| `content/voices.json` | Voice per language and role, runtime (medium) and prerender (high allowed), role synthesis settings; pt_PT `dev_only` (D105) | `tools/check_licences.py` (FT-AUD-014) |

A line's text may hold slots, `{name}`, declared in `slots` with a kind: `ship_name`, `callsign`, `npc_name` (the closed set, synthesised at Start) or `number` (stitched from fragments; `feminine` lists the languages where the counted noun is feminine). The coalescing key may use slots too (`contact:{callsign}`).

## Build time: prerender (FT-AUD-002, FT-DAT-005)

`uv run --project tools/tts python tools/tts/prerender.py [LANG...] [--out DIR]` reads only `content/dialogue/*.json` and `content/voices.json`. Output (default `content/voice/prerendered/`, gitignored, never committed; exports include it) per language and role, read by `ClipLibrary` (`content/voice/clip_library.gd`):

- `DIR/<lang>/<role>.pcm`: one blob of 16-bit little-endian mono PCM;
- `DIR/<lang>/<role>.json`: `{"rate", "voice", "clips": {key: [first_sample, samples]}}`.

Keys: `line:<id>` (a line without slots, prerender voice), `seg:<id>:<k>` (the k-th literal piece of a slotted line's text in that language, split at the slots, empty pieces skipped; runtime voice, trimmed), `num:<key>` (numbers.json fragments; runtime voice, trimmed). Computer clips are not filtered here: the robotic filter is an effect chain on the client's `VoiceComputer` bus (FT-AUD-004, D153), so it applies alike to prerendered, stitched and synthesised clips and to either Piper build.

## Host: synthesis and streaming (`net/voice/`)

Clients play authored lines without slots from their own export (`local` lines); the host stitches slotted lines from segments, cached names and number fragments (`NumberWords`, `shared/number_words.gd`) and synthesises free text, and streams those clips only to the client that plays each (D152). `VoiceService` (a `Node` composed next to `NetServer`):

- one persistent Piper process per voice behind a thin adapter: `tools/tts/piper_stream.py` (piper-tts 1.8.0, development) or the standalone rhasspy/piper 2023.11.14-2 binary (releases), each driven by its own worker thread; the main loop only queues requests and collects finished parts (FT-AUD-019, FT-ARC-019);
- `start_session(lang, closed_set)` at Start: loads the language's prerendered blobs and synthesises every closed-set name in each role's voice, trimmed and cached (FT-AUD-018);
- `say(line_id, args, audience)`: an authored line with no synthesis: a line without slots is sent as a `local` event only; a slotted one is stitched and streamed;
- `say_free(text, role, priority, audience)`: runtime synthesis, streamed per sentence; with more than 4 free-text lines queued for synthesis, further ones are subtitles only (D110);
- routing hooks for #10's main lead: `npc_audience` (the NPC's conversation claimer, FT-AUD-005) and `computer_audience` (clients holding the stations concerned, FT-AUD-006).

Per line it sends one reliable event and the clip:

- Event `voice_line`, high lane, before any audio: `{clip, line, text, role, priority, max_age_ms, coalesce, resume, audio, local}`; `text` is already in the session language with slots filled; `audio` false means subtitles only; `local` true means the client plays `line:<line>` from its own `ClipLibrary` and no VOICE message follows.
- Message `VOICE` (type 17), low lane (one chunk per pump behind snapshots, FT-NET-038): `{clip, rate, pcm, part, last}`, one per sentence or stitched clip; `last` ends the clip (PROVISIONAL, D150).

## Client

- `VoiceBus` (pure logic, injected clock, no audio): P0 > P1 > P2 > P3; a higher priority preempts (80 ms fade, then resume or drop per the line's flag); equal priority queues; a queued line older than its max age, or superseded by a newer line with its coalescing key, is dropped (FT-AUD-007, FT-AUD-008, FT-AUD-011).
- `SubtitleFeed`: every `voice_line` event shows at once, whatever happens to its audio (FT-AUD-010).
- `VoicePlayer` (`Node`): feeds the bus from a `NetClient` and a `ClipLibrary`, and plays NPC lines on the `Voice` audio bus and computer lines on `VoiceComputer`, whose effects approximate S7's robotic chain (FT-AUD-004).
