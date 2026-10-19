# spikes/

Throwaway M0 spike code (#3, spec §2.4). One folder per spike (`s2/`, `s4/`, …); results in `docs/spikes/<Sx>.md`.

- Excluded from the game exports (`export_presets.cfg`) and outside the §2.2 module rules, so `tools/lint_arch.py` doesn't apply its purity checks here. GDScript here still passes `gdlint`, `gdformat` and typed `--check-only` (`gate.sh l0`).
- `class_name`s carry the spike prefix (`S6Ship`) so they don't collide in the global class list.
- Only the parts named in #3 are promoted, by the M1 issues: the S5 integrator (T027), the S4 reconnect, resync and chunking logic (T045, #6), the S3 static server and keep-awake (#6), and possibly the S5 widgets (T050).
- Generated audio, builds and screenshots never go in the repo.
