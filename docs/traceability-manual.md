# Manually verified FT ids

Ids verified by a review item, playtest or owner step rather than a test. One line per id: `- FT-AREA-NNN <issue link> <how>`. `tools/traceability.py --check` fails on an entry without an issue link (FT-TST-017).

- FT-LIC-002 https://github.com/migueltorrescosta/full-theta/issues/2 "No EmptyEpsilon code" item in `.github/pull_request_template.md`, checked on every PR.
- FT-LIC-003 https://github.com/migueltorrescosta/full-theta/issues/2 `docs/provenance.md` keeps the EmptyEpsilon clone outside the repository.
- FT-LIC-004 https://github.com/migueltorrescosta/full-theta/issues/2 `docs/provenance.md` carries the §13.2 record, reviewed when a mechanic changes.
- FT-DAT-012 https://github.com/migueltorrescosta/full-theta/issues/2 Same review item as FT-LIC-002.
- FT-TST-002 https://github.com/migueltorrescosta/full-theta/issues/2 `tools/gate.sh ci` runs headless with no GPU on fugaku and the GitHub runner.
- FT-TST-004 https://github.com/migueltorrescosta/full-theta/issues/2 `.github/workflows/ci.yml` runs `gate.sh ci` on every ready PR and skips drafts.
- FT-TST-005 https://github.com/migueltorrescosta/full-theta/issues/2 `gate.sh` prints the commit and per-tier results; PR bodies record them (`.github/pull_request_template.md`).
- FT-GEN-012 https://github.com/migueltorrescosta/full-theta/issues/2 Linux and Windows export through `gate.sh l6`; macOS export recorded in `docs/spikes/S1.md`, packaged in #12.
- FT-DAT-006 https://github.com/migueltorrescosta/full-theta/issues/2 `scenarios/` is the one scenario folder (`scenarios/README.md`); `tools/lint_arch.py` keeps it pure; the Scenario API comes in #10.
- FT-TST-019 https://github.com/migueltorrescosta/full-theta/issues/12 `tools/gate.sh l6` (`tools/l6/run.sh`): the exported Linux build and the Windows build under Wine synthesise a line with each bundled voice and serve their bundled web export to headless Chromium; the PR body records the passing commit.
- FT-ARC-017 https://github.com/migueltorrescosta/full-theta/issues/13 The release workflow builds the macOS package with the Piper helper (`docs/release.md`); signing, notarisation and a run on a Mac are the owner step in #13.
