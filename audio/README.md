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

`uv run --project tools/tts python tools/tts/prerender.py [LANG...] [--out DIR] [--host-out DIR] [--dev]` reads only `content/dialogue/*.json` and `content/voices.json` and writes two packs per language (D152, D154). Both folders are gitignored; generated audio is never committed. A `dev_only` language (pt_PT until #16) is refused without `--dev`.

- **Client pack**, `audio/prerendered/<lang>/`, in desktop and web exports: `<line id>.ogg`, Ogg Vorbis (about 53 kbps), one per line without slots (the role's prerender voice). Clients load them with `LocalLines` (`audio/local_lines.gd`).
- **Host pack**, `audio/prerendered_host/<lang>/`, desktop exports only: per role `<role>.pcm`, one blob of 16-bit little-endian mono PCM, and `<role>.json`, `{"rate", "voice", "clips": {key: [first_sample, samples]}}`. Keys: `seg:<id>:<k>` (the k-th literal piece of a slotted line's text in that language, split at the slots; only pieces holding a letter are rendered) and `num:<key>` (numbers.json fragments, cut at the first 200 ms silence because voices babble after a single word), both in the role's runtime voice, trimmed and peak-normalised. The host loads them with `ClipLibrary` (`content/voice/clip_library.gd`), composed by `VoiceSetup`.
- Each language folder of both packs gets `index.json`, `{"language", "clips": [files]}`, which the package inspection checks. The release build calls `tools/tts/prerender_release.py --out audio/prerendered LANG...` (packaging's hook).

Computer clips are not filtered here: the robotic filter is an effect chain on the client's `VoiceComputer` bus (FT-AUD-004, D153), so it applies alike to local, stitched and synthesised clips and to either Piper build.

Files read at runtime, which every export must include: `content/dialogue/*.json`, `content/voices.json`, `content/i18n/strings.json`, `audio/prerendered/**` (desktop and web) and `audio/prerendered_host/**` (desktop).

## Host: synthesis and streaming (`net/voice/`)

Clients play authored lines without slots from their own export (`local` lines); the host stitches slotted lines from segments, cached names and number fragments (`NumberWords`, `shared/number_words.gd`) and synthesises free text, and streams those clips only to the clients in the line's audience (D152). `VoiceService` (a `Node` composed next to `NetServer`):

- one persistent Piper process per voice behind a thin adapter: `tools/tts/piper_stream.py` (piper-tts 1.8.0, development) or the standalone rhasspy/piper 2023.11.14-2 binary (releases), each driven by its own worker thread over non-blocking pipes (stderr read and dropped); the main loop only queues requests and collects finished parts (FT-AUD-019, FT-ARC-019). A launch or request past its deadline (PROVISIONAL, scaled by text length) kills and restarts the process and fails the request (subtitles only); a process that died while idle is relaunched before the next request; a job whose voice hands over nothing for `JOB_TIMEOUT_MS` fails in `VoiceService`, so the D110 count drops and Start completes;
- composed by `VoiceSetup` (`app/voice_setup.gd`): host clips from `res://audio/prerendered_host`, and the synth factory (`BundledPiper`'s binary in exports, found at runtime; the tools/tts venv in development; `FT_PIPER_BIN` forces the binary). Without a voice model, or with a `dev_only` language in a release build, lines are subtitles only;
- `start_session(lang, closed_set)` at Start (T043 calls it): loads the language's host pack and synthesises every closed-set name in each role's voice, trimmed and normalised on the synth's worker thread and cached; when both roles share a voice with equal effective settings (the binary's process-wide settings), each name is synthesised once and shared (FT-AUD-018);
- `say(line_id, args, audience)`: an authored line with no synthesis: a line without slots is sent as a `local` event only; a slotted one is stitched and streamed;
- `say_free(text, role, priority, audience)`: runtime synthesis, streamed per sentence (text cut at a space to `MAX_FREE_CHARS`, 400, PROVISIONAL, for synthesis; the subtitle keeps it all; parts capped at `PiperProcessSynth.MAX_PART_BYTES`); with more than 4 free-text lines queued for synthesis, further ones are subtitles only (D110);
- routing hooks for #10's main lead: `npc_audience` (the NPC's conversation claimer, FT-AUD-005) and `computer_audience` (clients holding the stations concerned, FT-AUD-006).

Per line it sends one reliable event and the clip:

- Event `voice_line`, high lane, before any audio: `{clip, line, text, role, priority, max_age_ms, coalesce, resume, audio, local}`; `text` is already in the session language with slots filled; `audio` false means subtitles only; `local` true means the client plays `res://audio/prerendered/<lang>/<line>.ogg` from its own export and no VOICE message follows.
- Message `VOICE` (type 17), low lane (one chunk per pump behind snapshots, FT-NET-038): `{clip, rate, pcm, part, last}`, one per sentence or stitched clip; `last` ends the clip and may be an empty part (D150).

## Client

- `VoiceBus` (`voice_bus.gd`, pure logic, time passed in, no audio; FT-AUD-011): P0 > P1 > P2 > P3; a line starts once the part it starts from has arrived; a higher priority preempts (`FADE_MS` 80 ms fade, then the line resumes from where its fade began or is dropped, per its `resume` flag); equal priorities queue FIFO; a queued line older than its max age, or superseded by a newer line with its coalescing key (even one with `audio` false), is dropped (FT-AUD-007, FT-AUD-008). Parts play in order and back to back; a missing next part makes the line wait (an underrun), and a line starved for `STALL_MS` is dropped. `dropped` records why (expired, coalesced, preempted, stalled). It plays through a `VoiceSink` (`voice_sink.gd`).
- `SubtitleFeed` (`subtitle_feed.gd`): every `voice_line` event shows at once, whatever happens to its audio, labelled with the UI string `subtitle.<role>` (FT-AUD-010).
- `VoicePlayer` (`voice_player.gd`, a `Node`): the station UI forwards each `NetClient.take_events()` event to `handle_event(event) -> bool` (false: not a voice line) and calls `pump(client)` after `client.poll()`; `subtitle(entry)` fires per line. A line with `local` true plays its prerendered Ogg Vorbis file through `local_lines` (`LocalLines`, `local_lines.gd`: `res://audio/prerendered/<lang>/<line_id>.ogg`, loaded as an imported resource or, before an import, from disk; a line id that doesn't match the dialogue schema's id pattern, or a language outside `I18n.LANGUAGES`, gives no file); it is ready at once, plays and resumes by position, and a missing file leaves the subtitle only. It plays through `VoiceStreamSink`: one `AudioStreamPlayer` per voice bus (`Voice`, `VoiceComputer`), so an NPC line and a computer line never share a player, fade or stop each other; streamed parts go through an `AudioStreamGenerator`, gapless, and a finished line's buffered tail plays out before the next line on its bus; local lines play as their own stream. The sink reports what was really heard (`VoiceSink.played`: frames the generator consumed, or the stream position, less the output latency), and `VoiceBus` resumes a preempted line from that when it is behind its clock, and keeps parts the sink still buffers. A line needing another stream on the same bus (local after streamed, the reverse, or another sample rate) still drops the previous line's buffered remainder, at most the generator's lag.
- Buses (`voice_buses.gd`, created at runtime when missing): NPC lines play on `Voice`; computer lines on `VoiceComputer`, sent to `Voice`, whose effects approximate the S7 robotic filter (6 ms comb, 300–3,400 Hz band-pass, lo-fi bitcrush; no ring modulation, which has no built-in effect) (FT-AUD-004).

## Release packages

- `bundled_piper.gd` (`BundledPiper`): where a release package keeps Piper, its eSpeak NG data and the voices, and a blocking one-line synthesis for the L6 smoke test (D140, `docs/release.md`).
