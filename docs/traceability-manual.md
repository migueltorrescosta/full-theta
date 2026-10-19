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
- FT-TST-011 https://github.com/migueltorrescosta/full-theta/issues/6 `tools/gate.sh l4` (`tools/l4/scenarios/`): join, coverage, claims, reconnect after a kill, pause and resume, host crash and orphan rejoin; the L3 suite in `tests/net/` covers the 64-connection limit (`test_host_server_services.gd`).
- FT-TST-014 https://github.com/migueltorrescosta/full-theta/issues/6 `tools/l4/run.sh` pins the server and every client to 2 cores (`taskset -c ${L4_CPUS:-0,1}`); 10 runs in a row recorded in the PR body.
- FT-AUD-015 https://github.com/migueltorrescosta/full-theta/issues/10 The latency half (p95 under 1 s over 50 free-text lines) is measured by `tools/voice_latency/` (S7b method) and recorded in the PR body; the D110 subtitles-only overflow is unit-tested.
- FT-TST-019 https://github.com/migueltorrescosta/full-theta/issues/12 `tools/gate.sh l6` (`tools/l6/run.sh`): the exported Linux build and the Windows build under Wine synthesise a line with each bundled voice and serve their bundled web export to headless Chromium; the PR body records the passing commit.
- FT-ARC-017 https://github.com/migueltorrescosta/full-theta/issues/13 The release workflow builds the macOS package with the Piper helper (`docs/release.md`); signing, notarisation and a run on a Mac are the owner step in #13.
