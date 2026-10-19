# Releases

A release is a set of packages for Linux, Windows and macOS, built from one tagged commit by `.github/workflows/release.yml`. The workflow runs only on version tags (`v*`); PRs and `main` keep the single gate job in `ci.yml` (FT-TST-004). Each package carries everything the host must serve or run (FT-ARC-022, TECH-4): the game, the web export of the same commit for browser stations, and Piper with the release voices, plus the licence material a GPL release needs (FT-LIC-008).

## Cutting a release

1. Pick the release commit on `main`. On fugaku, run `tools/gate.sh all` on it; `l6` must pass (FT-GEN-012, FT-TST-019). Record the output in the release PR or the owner issue.
2. The owner approves in #13 (Windows smoke test, macOS signing). Only then:
   ```bash
   git tag -a v0.1.0 -m "Full Theta v0.1.0" <commit> && git push origin v0.1.0
   ```
3. The workflow's `package` job builds and inspects the packages with a read-only token. Its `draft` job, the only one that can write and which runs no repository code, drafts a GitHub release with the packages, `SHA256SUMS`, the source archives and notes filled from `.github/release-notes.md` (`tools/release/notes.py`). Nothing is public until the owner publishes the draft.
4. The owner edits the draft's Changes section and ticks the checks. Next, the owner replaces the unsigned macOS zip with the signed one from #13 under the same name, and regenerates the checksums and the Downloads list:
   ```bash
   gh release download v0.1.0 -D rel && cp <signed zip> rel/full-theta-v0.1.0-macos.zip
   (cd rel && sha256sum full-theta-* piper-* espeak-ng-* >SHA256SUMS)
   gh release upload v0.1.0 rel/full-theta-v0.1.0-macos.zip rel/SHA256SUMS --clobber
   uv run --project tools python tools/release/notes.py --version v0.1.0 --commit <commit> rel
   ```
   The last command prints the notes with the new Downloads list; paste that section into the draft. Then the owner publishes it.

A tag whose packages fail inspection fails the workflow. Delete the tag, fix, and tag again.

## Artefacts

| Asset | Contents |
|---|---|
| `full-theta-V-linux-x86_64.tar.gz` | `full-theta.x86_64`, `web/`, `piper/` (the `piper` program, its libraries, `espeak-ng-data/`, `voices/`), `LICENSE`, `licenses/`, `SOURCE.md`, `BUILD.json` |
| `full-theta-V-windows-x86_64.zip` | The same, with `full-theta.exe` and `piper/piper.exe` and its DLLs |
| `full-theta-V-macos.zip` | `Full Theta.app` (Piper in `Contents/Helpers/piper/`, its data and voices in `Contents/Resources/piper/`, the web export in `Contents/Resources/web/`), and `LICENSE`, `licenses/`, `SOURCE.md`, `BUILD.json` beside it |
| `full-theta-V-source.tar.gz` | `git archive` of the tagged commit |
| `piper-…`, `piper-phonemize-…`, `espeak-ng-<commit>.tar.gz` | The upstream sources of the bundled Piper and eSpeak NG, which `SOURCE.md` offers. Piper's is its release tag. Upstream built piper-phonemize and eSpeak NG from their master branches and recorded no commit, so these are the commits those branches pointed at on the build date (`derivation` in `tools/release/piper.json`); `SOURCE.md` says so and offers the source on request as well |
| `SHA256SUMS` | SHA-256 of every asset |

The game finds its bundled files next to its executable (`ReleaseBundle`, `BundledPiper`). The Host button's server child serves `web/` (`HostLauncher`).

## How the build works

`tools/release/build.sh VERSION OUT_DIR` does every step; the workflow and `gate.sh l6` both call it. VERSION must look like `v1.2.3` or `v1.2.3-rc.1`. The script refuses an OUT_DIR that holds anything other than an earlier build's output, and writes `.gdignore` there, so Godot never imports or exports build files.

1. Writes `build_info.json` (version, commit). It is gitignored, and every export packs it, so the desktop build and the web page both print `build: VERSION COMMIT` at start (`ReleaseBundle.build_line()`).
2. Prerenders every release language (`tools/release/prerender.sh`, D154): the client clips into `audio/prerendered/<lang>/` (every pack, web included) and the host's stitching fragments into `audio/prerendered_host/<lang>/` (desktop packs only). It renders with the `prerender` voices of `tools/tts/voices.json`, which don't ship. The packs carry the clips through the export include filter, together with the dialogue and string data the game reads (`content/dialogue/*.json`, `content/i18n/strings.json`, `content/voices.json`), and the inspection checks both in every pack (D150–D152). Until the voice strand adds `tools/tts/prerender_release.py`, the step writes stub indexes. The inspection rejects them unless `--allow-stub-prerender` is given, so a tag can't ship without clips.
3. Exports the `Linux`, `Windows`, `macOS` and `Web` presets.
4. Finishes the web export for plain `http://` (`tools/release/web_patch.py`, D108).
5. Packages everything (`tools/release/package.py`). It fetches the pinned Piper archives, licence files and sources (`tools/release/fetch.py`, `tools/release/piper.json`) and the release voices (`tools/tts/fetch_voices.py`), all checked by SHA-256.
6. Inspects the packages (`tools/release/inspect_packages.py`) and fails the build on any problem:
   - It compares each package's file list exactly with the exports, the pinned upstream Piper archive, the release voices and the licence files, so a missing or extra file fails.
   - It reads `build_info.json` from inside each desktop pack and each web pack, so it checks that the commit matches the tag.
   - It checks the data files and prerendered clips in each pack, the patched shell and `index.js`, the voice configs (D144) and the macOS helper's rpath.
   - It checks the GPL-3.0 text, `SOURCE.md`'s versions and source archives, and that the folder holds exactly the expected assets, each listed in `SHA256SUMS`.

## L6 on fugaku

`tools/gate.sh l6` (`tools/l6/run.sh`) builds and inspects the packages of the working tree. Then, for the Linux package natively and the Windows package under Wine, it runs three checks:

- The exported game synthesises one line with each bundled voice through its bundled Piper (`-- --tts-smoke TEXT --out /ABS/line.wav`), under a 300 s timeout.
- It serves its bundled `web/`, and headless Chromium loads the page from a non-secure host name until the page prints the same build line.
- A headless server smoke run.

The macOS package is built and inspected, not run. L6 needs `wine`, `node` (it runs `npm ci` in `tools/l6/` once) and Playwright's Chromium headless shell. Logs are in `build/l6/run/`.

## Dry run

To rehearse a release without publishing, run the workflow under [act](https://github.com/nektos/act) on a throwaway tag (the draft step is skipped under act):

```bash
git clone -q . /tmp/ft-dryrun && cd /tmp/ft-dryrun && git tag v0.0.0-dryrun
echo '{"ref": "refs/tags/v0.0.0-dryrun"}' >/tmp/tag-event.json
act push -W .github/workflows/release.yml --eventpath /tmp/tag-event.json \
  -P ubuntu-latest=catthehacker/ubuntu:act-latest \
  --container-options "-v $HOME/.cache/full-theta:/root/.cache/full-theta:ro"
```

A clone keeps the run's `build_info.json` and prerender folders out of your working tree. The read-only cache mount reuses fugaku's fetched engine, templates, Piper and voices (drop it where the cache is empty). Under act, the inspection accepts stub prerendered clips. act doesn't apply the `tags` filter, so it can't show that branch pushes skip the workflow; GitHub runs a workflow whose `push` trigger lists only `tags` for tag pushes alone.

Or run the same build directly: `tools/release/build.sh v0.0.0-dryrun build/dryrun --allow-stub-prerender`.

## Changing what ships

- **Voices:** the `release` list in `tools/tts/voices.json` (D141). Each voice needs a `Piper voice <name>` entry in `content/provenance.json` (the build fails without one) and must pass the S7 audit (FT-LIC-007, D105). The release languages follow from the voices.
- **Voice configs:** the bundled Piper rejects phonemes of more than one codepoint, so `package.py` drops them from each voice's `.onnx.json` and notes the change in `licenses/VOICES.md` (D144). Record any such change in the voice's `content/provenance.json` entry too.
- **Piper:** `tools/release/piper.json` pins the archives, licence files and source archives with their SHA-256 (D140). The program's interface is fixed by `BundledPiper`; the runtime adapter (E10) uses the same paths.
- **Engine upgrade:** the web shell (`app/web/shell.html`, godotengine/godot#124636) and the `index.js` guard (`tools/release/web_patch.py`, godotengine/godot#124637) are workarounds. `tools/tests/test_release.py` fails when the pinned templates' `index.js` no longer holds the patched pattern. Check both issues and drop each patch once it is fixed upstream. `tools/release/pck.py` reads pack format 4 (Godot 4.7); a new format fails the inspection.

## macOS

The macOS package is unsigned (FT-ARC-017). The owner signs and notarises the app and its Piper helper in #13. `rhasspy/piper` 2023.11.14-2's macOS archives ship without their libraries, and both are x86_64. The package therefore takes `piper` from the x64 archive and the dylibs from `piper-phonemize` 2023.11.14-4, and adds an `@executable_path` rpath with `llvm-install-name-tool` (D140). On Apple silicon, Piper runs under Rosetta 2. Nothing on fugaku can run it, so the first check on a Mac (#13) must synthesise a line: `Contents/Helpers/piper/piper --model …/voices/en_GB-cori-medium/en_GB-cori-medium.onnx --espeak_data …/espeak-ng-data --output_file /tmp/a.wav <<< "Hello"`. For a local test before signing, `codesign --force --deep -s - "Full Theta.app"` ad-hoc signs the bundle.

## Owner smoke tests (#13)

- **Windows:** unzip on a Windows PC and run `full-theta.exe`. Host a session and open the host's address on a tablet; the page must load. One spoken line must play.
- **macOS:** after signing, open the app and host a session. The tablet page must load, and the Piper helper must speak, through Rosetta on Apple silicon.
- **Linux:** L6 covers it on fugaku. An owner run on another distribution is welcome.
