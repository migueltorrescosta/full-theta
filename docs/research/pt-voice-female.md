# A female European Portuguese voice: dataset search

Sources: LibriVox catalogue and reader pages, the LibriVox API, archive.org item metadata, OpenSLR 94 (MLS) and 146 (CML-TTS) with the MLS Portuguese `metainfo.txt` and the CML-TTS segment lists, Project Gutenberg, Mozilla Common Voice discussions. Bead w-nct (child of w-r57).

## Requirements

The game redistributes the trained model, so the licence must allow commercial use and derivatives (public domain, CC0, CC BY or MIT; not NC or ND). The data must come from one female speaker with a European Portuguese accent, about 1 h or more of clean read speech (the male voice, tugão, has 1.36 h).

## Candidates

| Candidate | Licence | Accent evidence | Female hours | Quality | Verdict |
|---|---|---|---|---|---|
| OHF voice-datasets | CC0 | Only tugão for pt_PT | 0 | Studio | No female voice |
| TTS-Portuguese Corpus | CC BY 4.0 | Brazilian | 0 (male) | Good | Reject |
| TAGARELA | CC BY-NC-SA | Brazilian | n/a | n/a | Reject: NC |
| Common Voice pt | CC0 | No reliable pt-PT tag; free-text accents mostly Brazilian | Under 1 h per speaker, typically | Mixed microphones | Reject |
| MLS Portuguese (OpenSLR 94) | CC BY 4.0 | Reader 2961 "Leni" (87.4 h) reads mainly Brazilian authors and writes Brazilian Portuguese in her summaries ("uma de suas obras"); reader 12249 Adriana Sacciotto (18.2 h) reads mainly Brazilian authors solo | 87.4 h and 18.2 h, probably Brazilian | LibriVox, varied | Reject: probably Brazilian; transcripts are lowercase without punctuation |
| CML-TTS Portuguese (OpenSLR 146) | CC BY 4.0 | The same LibriVox readers as MLS (segment lists checked) | As MLS | 24 kHz, punctuated | Reject: as MLS |
| LibriVox: Carina Pereira (reader 9056) | Public domain | Website "The Portuguese Storyteller" (now gone); reads Eça de Queirós | 7.3 h in the group project *Contos* (Eça) | Not checked | Backup |
| **LibriVox: L.S.B.Seabra (reader 14064, "Sofia Seabra")** | **Public domain** | Reads only Portuguese authors solo; her summaries use European Portuguese ("rapariga", "acaba por proteger", "ao se aperceber", "singrar na vida", "Sumário") | **About 72 h solo** across 7 books, after the MLS cut-off | 44.1 kHz VBR MP3, peaks at -3 dBFS, RMS at -27 dBFS, pauses gated to silence | **Chosen** |

Accent and gender were not checked by ear. The evidence for L.S.B.Seabra is her written variety, her choice of books and a crude pitch estimate: a median of about 222 Hz over 90 s, against 178 Hz for tugão by the same method. Confidence that she is a female European Portuguese speaker: medium-high (about 80 %). Someone needs to listen to a few clips before training.

## Licence

LibriVox states that all its recordings are in the public domain and may be used for any purpose, including commercial use. The status is certain in the USA, and LibriVox says it may hold in other countries too. The texts are public domain everywhere (Eça de Queirós died in 1900). No attribution is required. Credit "L.S.B.Seabra / LibriVox" in the model card anyway.

## Verdict

Use L.S.B.Seabra's reading of *O Mandarim* (Eça de Queirós; 2.35 h in 9 sections; Project Gutenberg #16384 for verification). She has about 70 h more solo work (*O Primo Bazilio*, *Os Fidalgos da Casa Mourisca*, *Uma Família Ingleza*, *A Relíquia*, *A Cidade e as Serras*, *O mysterio da estrada de Cintra*) if the voice needs more data.

LibriVox chapters must be cut into clips with matching text. The plan uses Whisper word timestamps to cut at pauses. A clip is kept only when its text matches the 1880 Gutenberg text word for word, after the old spelling is folded to modern forms. The labels keep Whisper's modern spelling, which suits espeak-ng `pt`.

## Where the data lives

The audio, the scripts and the run-by-hand commands are on fugaku in `~/ft-artifacts/pt-voice-f/`, outside the repository. See its `README.md`. The owner runs two commands: `prep.sh` transcribes and cuts the clips, and `train.sh` mirrors the tugão training. Agents may not install or run the third-party ASR or Piper code. No audio or weights are committed.
