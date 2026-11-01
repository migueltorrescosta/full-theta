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
2. Prerenders every release language (`tools/release/prerender.sh`, D154): the client clips into `audio/prerendered/<lang>/` (every desktop pack; the web pack carries none, see step 4) and the host's stitching fragments into `audio/prerendered_host/<lang>/` (desktop packs only). It runs `tools/tts/prerender_release.py` (`audio/README.md`) with the `prerender` voices of `tools/tts/voices.json`, which don't ship, and the runtime (`release`) voices for the host pack. The packs carry the clips through the export include filter, together with the dialogue and string data the game reads (`content/dialogue/*.json`, `content/i18n/strings.json`, `content/voices.json`), and the inspection checks both in every pack (D150–D152). A language with no clips fails the inspection.
3. Exports the `Linux`, `Windows`, `macOS` and `Web` presets.
4. Finishes the web export for plain `http://` (`tools/release/export_web.sh`, which exports the `Web` preset and runs `tools/release/web_patch.py`, D108): the AudioWorklet guard, both keep-awake videos, content-hashed names for the wasm, pack and worklets (`index.<hash>.wasm`, served `immutable`, D197) and gzip copies. Each language's clips ship beside the page as `voice-<lang>.pack`, with `.gz` and `.br` copies, and the browser fetches the session language's pack after the welcome. It uses the slim engine template when one is built (see Web build); in a release build (`FT_REQUIRE_SLIM_WEB_TEMPLATE=1`, which `build.sh` sets) it fails instead of falling back to the stock one.
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

A clone keeps the run's `build_info.json` and prerender folders out of your working tree. The read-only cache mount reuses fugaku's fetched engine, templates, Piper and voices (drop it where the cache is empty). act doesn't apply the `tags` filter, so it can't show that branch pushes skip the workflow; GitHub runs a workflow whose `push` trigger lists only `tags` for tag pushes alone.

Or run the same build directly: `tools/release/build.sh v0.0.0-dryrun build/dryrun`.

## Changing what ships

- **Voices:** the `release` list in `tools/tts/voices.json` (D141). Each voice needs a `Piper voice <name>` entry in `content/provenance.json` (the build fails without one) and must pass the S7 audit (FT-LIC-007, D105). The release languages follow from the voices.
- **Voice configs:** the bundled Piper rejects phonemes of more than one codepoint, so `package.py` drops them from each voice's `.onnx.json` and notes the change in `licenses/VOICES.md` (D144). Record any such change in the voice's `content/provenance.json` entry too.
- **Piper:** `tools/release/piper.json` pins the archives, licence files and source archives with their SHA-256 (D140). The program's interface is fixed by `BundledPiper`; the runtime adapter (E10) uses the same paths.
- **Engine upgrade:** the web shell (`app/web/shell.html`, godotengine/godot#124636) and the `index.js` guard (`tools/release/web_patch.py`, godotengine/godot#124637) are workarounds. `tools/tests/test_release.py` fails when the pinned templates' `index.js` no longer holds the patched pattern. Check both issues and drop each patch once it is fixed upstream. `tools/release/pck.py` reads pack format 4 (Godot 4.7); a new format fails the inspection.

## Web build

Browser stations load the web export from the host's own HTTP server (`net/static_server.gd`). Two things keep the load short on a phone (D197): a **slim engine template** and **caching**. The wasm, pack and audio worklets carry a content hash in their names, so `StaticServer` sends them `Cache-Control: immutable` and a returning browser never asks again; `index.js` and the page are revalidated by ETag. (A service worker would also cache them, but browsers allow one only in a secure context, which a LAN `http://` page isn't.) While the engine starts, the page shows a loading screen with scrolling tips (`app/web/shell.html`).

`tools/release/build_web_template.sh` builds the slim template: Godot 4.7.2-stable from source with emsdk 4.0.11 (the version the engine's own CI uses), the no-threads web target, `optimize=size`, full LTO, and the modules and servers the game doesn't use off (3D rendering stays: the Helm and Viewer scenes use it). The result goes to `~/.cache/full-theta/web-template/web_nothreads_release.zip`, where `export_web.sh` finds it; without it the export uses the stock template. `FT_STOCK_WEB_TEMPLATE=1` forces the stock one. The recipe, flags and numbers are in `BUILD.txt` beside the zip and in the table below.

Measured on fugaku, the same page and server, headless Chromium on 2 cores with software rendering (a CPU-bound number, so only the ratios carry over to a phone):

| | Stock template | Slim template |
|---|---|---|
| `index.wasm` | 39.5 MB (10.1 MB gzip) | 26.3 MB (6.6 MB gzip), 34 % smaller |
| Engine started (`startGame` resolved), 3 loads | 4.6, 6.0 and 4.0 s | 3.1, 3.0 and 2.9 s |
| Template build | none | 675 s with `-j8` on a quiet machine (1,309 s on a busy one), mostly the full-LTO link |

The 10 s join budget on a phone (S3 took 12.2 s, mostly engine start-up) is the owner's device check (#9): the first join on the slim build with a cold cache, then one with a warm cache. The pack is 0.8 MB, so the wasm decides. On GitHub the release workflow builds the template (D211): the `web-template` job restores `~/.cache/full-theta/web-template` from `actions/cache`, keyed by the hash of `tools/release/build_web_template.sh` (which pins emsdk, now 4.0.11, and the SCons flags) and `tools/godot-version`. On a miss it runs the script with `-j$(nproc)` (installing emsdk and SCons in user space and cloning the pinned Godot source) and the cache is saved when the job ends. The `package` job needs it, restores the same key with `fail-on-cache-miss`, and `build.sh` exports the web build with `FT_REQUIRE_SLIM_WEB_TEMPLATE=1`, so a missing template stops the release rather than shipping the stock one. No secret is involved. Bump emsdk by editing the script's `EMSDK_VERSION` default (the key changes with it). A cache saved on a tag ref is visible to reruns of that tag only, not to the next tag, so each new release tag builds the template once; a rerun of the same tag restores it. Running the release locally (`act`, `gate.sh l6`) uses the template already in `~/.cache/full-theta/web-template` (build it first with the script); under act the `web-template` job rebuilds it, so the dry run takes the build time too.

**Actions minutes per release run.** The template build from a clean checkout took 13.6 min wall (764 s of SCons, the rest emsdk install and the Godot clone) on 2 pinned cores of fugaku, 20 CPU-minutes and 7.9 GB peak memory, mostly the full-LTO link. On a GitHub runner expect 20 to 40 min the first time per tag (the repository is public, so the minutes are free and the runner has 4 vCPU and 16 GB; on a private 2 vCPU, 7 GB runner the link might run out of memory). A rerun of the same tag restores the cache: about 1 min for the `web-template` job. The `package` job then takes what it did before (the first run after this change is unmeasured). `timeout-minutes` is 120 for the template job.


## macOS

The macOS package is unsigned (FT-ARC-017). The owner signs and notarises the app and its Piper helper in #13. `rhasspy/piper` 2023.11.14-2's macOS archives ship without their libraries, and both are x86_64. The package therefore takes `piper` from the x64 archive and the dylibs from `piper-phonemize` 2023.11.14-4, and adds an `@executable_path` rpath with `llvm-install-name-tool` (D140). On Apple silicon, Piper runs under Rosetta 2. Nothing on fugaku can run it, so the first check on a Mac (#13) must synthesise a line: `Contents/Helpers/piper/piper --model …/voices/en_GB-cori-medium/en_GB-cori-medium.onnx --espeak_data …/espeak-ng-data --output_file /tmp/a.wav <<< "Hello"`. For a local test before signing, `codesign --force --deep -s - "Full Theta.app"` ad-hoc signs the bundle.

## Owner smoke tests (#13)

- **Windows:** unzip on a Windows PC and run `full-theta.exe`. Host a session and open the host's address on a tablet; the page must load. One spoken line must play.
- **macOS:** after signing, open the app and host a session. The tablet page must load, and the Piper helper must speak, through Rosetta on Apple silicon.
- **Linux:** L6 covers it on fugaku. An owner run on another distribution is welcome.
