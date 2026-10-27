# 9. Audio, TTS and languages

## 9.1 Voices

Piper voices speak NPC radio, ship-computer announcements and alerts (D38). Authored lines are prerendered at build time. The session's closed set (ship names, callsigns, NPC names) is synthesised at Start and cached per language; numbers are stitched from prerendered fragments; only free text is synthesised at runtime, which GPL-3.0 allows (D2, D38, D101). The ship computer uses Piper with a robotic/radio filter; there is no second engine (D71). Runtime and closed-set synthesis use medium-quality voices; high-quality voices only for prerendered lines (D105). Synthesis runs on the host server in one persistent Piper process per voice off the sim thread; each stitched or synthesised clip is streamed only to the client that plays it, so browser stations need no local Piper (D85, D101). Clients play authored lines without slots from their own export, as Ogg Vorbis; the host keeps the segments and number fragments it stitches from (D152, D154). The robotic filter is an effect chain on the client's ship-computer audio bus (D153).

## 9.2 Routing

Only the relevant client plays a line, usually the Comms player. If two players use Comms, only the one talking to that NPC hears it; until someone claims the conversation, every Comms holder of the ship hears its lines (D39, D238). English NPCs speak with `en_US-kristin-medium`, a voice distinct from the crew and computer voice; Italian NPCs use `it_IT-serena`; pt_PT NPC lines are subtitles only until #16 (D243). Ship-computer lines play on the stations they concern. Subtitles always show.

## 9.3 Voice bus

Priorities: P0 critical alarm > P1 ship computer > P2 NPC radio > P3 ambient. Higher priority preempts lower (80 ms fade, then resume or drop per line flag); equal priority queues; queued lines have a maximum age and coalescing keys. Alert tones play on a separate SFX bus never blocked by voice (tech.md §4.3).

## 9.4 Languages

English, Portuguese (pt_PT) and Italian at launch; one language per session (D40, D41).

## 9.5 Visual style

Semi-realistic science fiction with readable silhouettes: procedural geometry with panel detail, PBR-style metallic and roughness materials, a desaturated mint and violet palette, and at most a thin outline (D107, amending the toon look of v0.3 §8 and D63).

## 9.6 Requirements

- **FT-AUD-001** NPC radio, ship-computer announcements and alerts shall use offline Piper voices. (D38)
- **FT-AUD-002** Authored lines shall be prerendered at build time per language; generated audio shall not be committed. (D38)
- **FT-AUD-003** Dynamic lines (names, numbers, free text) shall be voiced with Piper as in FT-AUD-018 and FT-AUD-019. (D38, D101)
- **FT-AUD-004** The ship computer shall use a Piper voice with a robotic/radio filter. (D71)
- **FT-AUD-005** An NPC line shall play only on the client holding that NPC's conversation claim; while the conversation is unclaimed it shall play on every client holding Comms of that ship. (D39, D238)
- **FT-AUD-006** A ship-computer line shall play only on clients holding the stations it concerns. (D39)
- **FT-AUD-007** The voice bus shall order lines P0 > P1 > P2 > P3; a higher priority shall preempt a lower one. (v0.3 §8)
- **FT-AUD-008** Equal-priority lines shall queue; a queued line older than its maximum age or superseded by its coalescing key shall be dropped. (v0.3 §8)
- **FT-AUD-009** Alert tones shall play on a separate bus that voice never blocks. (v0.3 §8)
- **FT-AUD-010** Every spoken line shall also show as a subtitle. (v0.3 §8)
- **FT-AUD-011** The voice-bus queue logic shall be unit-testable without audio output. (v0.3 §11)
- **FT-AUD-012** The game shall launch with English, Portuguese (pt_PT) and Italian. (D40)
- **FT-AUD-013** A session shall use one language for all text and voice, chosen by the host. (D41)
- **FT-AUD-014** Every shipped Piper voice shall have a licence compatible with redistribution, recorded in the provenance manifest. (D2, D63)
- **FT-AUD-015** Runtime synthesis shall make a free-text line audible within 1 s of its event on the target client (verified by spike S7b); when more than 4 free-text lines are queued for synthesis, further lines shall show subtitles only, with no audio. (D38, D39, D101, D110)
- **FT-AUD-016** Art shall use procedural or primitive meshes and CC0 packs with semi-realistic PBR-style materials in the Compatibility renderer; sounds shall be CC0. (D63, D107)
- **FT-AUD-017** Browser clients shall unlock audio with a user gesture on join. (D8)
- **FT-AUD-018** The host server shall synthesise the session's closed set (ship names, callsigns, NPC names) at Start and cache it per language; numbers shall use prerendered fragments; runtime synthesis shall be used only for free text. (D85, D101)
- **FT-AUD-019** Synthesis shall run on the host server in one persistent Piper process per voice off the sim thread, and the host shall stream each dynamic clip only to the client that plays it. (D85, D101, plan review TECH-5)
