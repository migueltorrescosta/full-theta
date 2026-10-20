<!-- Release notes template, filled by tools/release/notes.py (docs/release.md).
     Lines in {{BRACES}} are filled automatically; edit the rest in the draft. -->
# Full Theta {{VERSION}}

Built from commit `{{COMMIT}}`.

## Changes

<!-- Owner: the player-facing changes since the last release. -->

## Downloads

One computer hosts: it runs the game, serves the browser stations and speaks
the ship's lines. Each package carries the web export of the same commit, so
tablets and phones join from the host's address in a browser.

{{ASSETS}}

- **Linux:** extract, then run `full-theta.x86_64`.
- **Windows:** extract, then run `full-theta.exe`.
- **macOS:** not signed or notarised until the owner step in #13, so macOS
  refuses to open it until then. The Piper helper is x86_64 and needs
  Rosetta 2 on Apple silicon.

## Voices

Spoken lines use Piper {{PIPER}} with these voices: {{VOICES}}. Languages with
a voice: {{LANGUAGES}}; other languages show subtitles only.

## Source and licences

Full Theta is GPL-3.0. Each package has `LICENSE`, `licenses/` and
`SOURCE.md`, which names the bundled Piper {{PIPER}} and eSpeak NG
{{ESPEAK_NG}}. Their source archives are listed under Downloads, next to the
game's own source.

## Checks

- [ ] `tools/gate.sh l6` green on fugaku on `{{COMMIT}}` (Linux and Windows packages, FT-TST-019, FT-GEN-012)
- [ ] Owner Windows smoke test (#13)
- [ ] macOS app and Piper helper signed and notarised (#13)
