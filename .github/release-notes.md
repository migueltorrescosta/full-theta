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
- **Windows:** extract, then run `full-theta.exe`. See "Opening it" below.
- **macOS:** extract, then open `Full Theta.app`. See "Opening it" below. The
  Piper helper is x86_64 and needs Rosetta 2 on Apple silicon.

## Opening it

The app is not notarised and the Windows build is not signed, so both systems
warn you the first time. The warning is expected. Do this once.

- **macOS:** right-click `Full Theta.app` and choose Open, then Open again. Or
  try to open it, then go to System Settings, Privacy & Security, and click
  Open Anyway.
- **Windows:** in the SmartScreen window click More info, then Run anyway.

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
- [ ] Owner macOS smoke test: Open anyway works and the helper speaks (#13)
