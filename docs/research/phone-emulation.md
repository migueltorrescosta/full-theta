# Web build on emulated phones (w-8yo, proxy for w-w2r)

fugaku has no phone, so the owner step w-w2r (measure the game on two real phones) is still open. This note measures the same things on emulated phones: headless Chromium with phone device descriptors and CPU throttling. The numbers are a stand-in. They locate the main costs, but they do not replace the real-phone measurement.

Build: `main` at `162bcf02`, exported with `tools/release/export_web.sh` (slim web template), measured on 2026-11-15.

## Method

A dedicated server serves the web build as `docs/launch.md` describes, on 127.0.0.1 only:

```
FT_DEV=1 godot --headless --path . -- --server --bind 127.0.0.1 --port 8701 \
  --http-root SITE --load-ships 6 --load-world 12 --no-beacon --grace-s 15
```

`--load-ships 6 --load-world 12` is the load-gate encounter (`LoadEncounter`): 6 crewable ships and 6 raiders of two factions that are hostile to each other and to the crew, so projectiles fly for the whole run. One `tools/l4/load_client.gd` process holds the other crew seats (35 seats with the phone on Helm, 36 with the phone on Viewer). Its Helms steer every 0.5 s and its Weapons fire every second. The stand-in crew joins only after the page reaches the lobby, so the fight starts while the page joins its station.

The page is opened as `http://ft-phone.lan:8700/?pick=helm&ready=1` (or `pick=viewer`). The host name maps to 127.0.0.1, so the page is not a secure context, as on a phone on the LAN. The `?pick=` test hook takes the station and presses Ready and Start (`WebAutoplay`). One tap in the lobby unlocks audio.

`measure_phone.js` (Playwright `playwright-core` 1.64.1 from `tools/l6`, headless Chromium shell) runs each case in a new browser context with an empty cache:

- Devices: Playwright's `Pixel 7 landscape` (mid-range, 863 x 360 CSS px, DPR 2.625) and `Galaxy S8 landscape` (old, 740 x 360, DPR 3). The game caps the canvas at DPR 2, so the canvases are 1726 x 720 and 1480 x 720.
- CPU: CDP `Emulation.setCPUThrottlingRate` 4 and 6, plus a 1x control.
- Network: CDP `Network.emulateNetworkConditions`, 50 Mbit/s down, 20 up, 5 ms latency (good home Wi-Fi).
- Graphics: default, or Graphics: Low with the 30 fps cap. The settings file (`client_settings.cfg`) is written into the page's IndexedDB file system before the game starts. The file that the game saves after joining shows `fps_cap=true low_graphics=true`, so the game read the seed.

Measured values:

- Join time: navigation start to the lobby (`window.ft.stage` becomes `ready`). Cold-join bytes: the sum of CDP `encodedDataLength` up to that point.
- Frames: on the station, after a 5 s warm-up, for 30 s. A Godot frame is a rAF tick in which the page clears its WebGL framebuffer. The table gives game frames per second and the p95 interval. rAF deltas agree with the game frames.
- CPU: the page main thread's CPU time per frame (CDP `ThreadTime`) and the SwiftShader GPU process's CPU time per frame (`/proc`).
- Memory: `performance.memory` JS heap, the wasm memory size, and the PSS of the page's renderer process.
- Audio: the web build plays audio through a `ScriptProcessorNode` on the main thread (2048 frames, 42.7 ms at 48 kHz). A callback gap longer than two buffers means the output ran dry. "Audio starved" is the share of the window that falls past two buffers. Chromium's own `AudioContext.playbackStats` reported 0 underruns in every run, because a late script processor outputs silence and the audio device itself never runs dry. The console showed no underrun messages.
- The server log (`--server-log`) adds the page's snapshot age and the game's own long-frame reports.

The run is valid only if the page stays on its station for the whole window. A destroyed ship moves the player to watching another ship. All runs in the tables were valid.

Each run starts a fresh server and stand-in crew. Everything runs on CPUs 8-11 (two physical cores and their hyper-threads) in `systemd-run` scopes capped at 6 GB. Other sessions shared fugaku: the 1-minute load average was 6-16 during the runs (the last column of the full table).

## Results

Emulated (headless Chromium, SwiftShader, CPU throttle), 2026-11-15, main `162bcf02`. One run per row; 30 s window.

| Device | CPU | Station | Graphics | Join to lobby (s) | Cold join (MB) | fps | Frame p95 (ms) | JS heap (MB) | Wasm (MB) | Page PSS (MB) | Audio starved |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Pixel 7 | 1x | Helm | Default | 13.0 | 12.6 | 2.6 | 546 | 60 | 190 | 492 | 80 % |
| Pixel 7 | 4x | Helm | Default | 26.7 | 12.6 | 2.2 | 702 | 62 | 190 | 493 | 83 % |
| Pixel 7 | 4x | Helm | Low+30fps | 26.6 | 12.6 | 2.7 | 575 | 126 | 190 | 554 | 77 % |
| Pixel 7 | 4x | Viewer | Default | 29.8 | 12.6 | 4.1 | 398 | 58 | 190 | 478 | 65 % |
| Pixel 7 | 4x | Viewer | Low+30fps | 30.9 | 12.6 | 4.0 | 407 | 100 | 190 | 520 | 65 % |
| Pixel 7 | 6x | Helm | Default | 40.1 | 12.6 | 1.9 | 954 | 125 | 190 | 554 | 85 % |
| Pixel 7 | 6x | Helm | Low+30fps | 49.9 | 12.6 | 2.3 | 661 | 125 | 190 | 555 | 83 % |
| Pixel 7 | 6x | Viewer | Default | 41.4 | 12.6 | 3.1 | 530 | 120 | 190 | 540 | 75 % |
| Pixel 7 | 6x | Viewer | Low+30fps | 47.9 | 12.6 | 2.9 | 553 | 57 | 190 | 477 | 75 % |
| Galaxy S8 | 1x | Helm | Default | 12.2 | 12.6 | 2.9 | 509 | 60 | 190 | 494 | 77 % |
| Galaxy S8 | 4x | Helm | Default | 28.6 | 12.6 | 2.8 | 561 | 126 | 190 | 558 | 77 % |
| Galaxy S8 | 4x | Helm | Low+30fps | 29.4 | 12.6 | 2.9 | 525 | 125 | 190 | 557 | 76 % |
| Galaxy S8 | 4x | Viewer | Default | 27.9 | 12.6 | 4.5 | 378 | 58 | 190 | 480 | 62 % |
| Galaxy S8 | 4x | Viewer | Low+30fps | 28.2 | 12.6 | 4.7 | 295 | 58 | 190 | 478 | 60 % |
| Galaxy S8 | 6x | Helm | Default | 40.8 | 12.6 | 2.9 | 554 | 127 | 190 | 557 | 76 % |
| Galaxy S8 | 6x | Helm | Low+30fps | 41.0 | 12.6 | 3.1 | 472 | 59 | 190 | 480 | 73 % |
| Galaxy S8 | 6x | Viewer | Default | 39.6 | 12.6 | 4.6 | 310 | 58 | 190 | 476 | 60 % |
| Galaxy S8 | 6x | Viewer | Low+30fps | 40.1 | 12.6 | 3.9 | 456 | 57 | 190 | 477 | 66 % |

At the devices' own pixel ratios, every frame waits for SwiftShader, so the frame rates above describe a software renderer, not a phone GPU. To see the main thread alone, a second pass forced the pixel ratio to 0.25 (a canvas of about 200 x 90 px, the same CSS layout):

| Device | CPU | Station | Graphics | fps | Frame p50 (ms) | Frame p95 (ms) | Main thread CPU per frame (ms) | Audio starved |
|---|---|---|---|---|---|---|---|---|
| Pixel 7 | 1x | Helm | Default | 4.4 | 226 | 375 | - | 64 % |
| Pixel 7 | 4x | Helm | Default | 5.4 | 176 | 278 | - | 53 % |
| Pixel 7 | 4x | Viewer | Default | 18.5 | 53 | 75 | 49 | 0 % |
| Pixel 7 | 6x | Helm | Default | 5.7 | 174 | 228 | 171 | 50 % |
| Pixel 7 | 6x | Helm | Low+30fps | 5.0 | 197 | 265 | 195 | 57 % |
| Galaxy S8 | 4x | Helm | Default | 6.2 | 154 | 254 | 149 | 47 % |
| Galaxy S8 | 6x | Helm | Default | 5.1 | 195 | 241 | 190 | 56 % |
| Galaxy S8 | 6x | Helm | Low+30fps | 5.0 | 197 | 262 | 197 | 57 % |
| Galaxy S8 | 6x | Viewer | Default | 11.7 | 83 | 124 | 81 | 8 % |

The full table, with the host load, the SwiftShader CPU per frame and the server's snapshot ages, is `table.md` next to this note. Raw results are `runs/*/m.json`, with a screenshot (`m.png`) and the server logs of each run.

## Findings

**Join.** A cold join downloads 12.6 MB in 4-5 requests over plain HTTP (gzip; R21-3 measured 12.5 MB). Over HTTPS the brotli files would be about 8.5 MB. The download takes about 3 s on the emulated Wi-Fi. The rest of the join is the engine starting (wasm compile, pack load, menu) and connecting: about 7 s at 1x, 21 s at 4x and 33 s at 6x. Join to lobby is 12-13 s at 1x, 27-31 s at 4x and 40-50 s at 6x. From lobby to the station takes another 8 s at 1x and 14-23 s throttled. The game's own long-frame reports show where: warming shaders in the lobby (2.3 s at 1x, 2.7 s at 4x, 3.6 s at 6x, median), showing the station (1.2 / 3.1 / 4.1 s) and building it (2.7 / 3.3 / 4.0 s).

**Main thread.** With the canvas made tiny, the main thread is busy for the whole frame under throttling. Helm costs about 150-200 ms of main thread per frame at 4-6x, which is about 30-37 ms of fugaku CPU per frame, and stays at 5-6 fps. Viewer costs 49 ms at 4x and 81 ms at 6x, about 13 ms of fugaku CPU, and reaches 12-18 fps. At full size and 1x, the main thread used 42-49 ms per Helm frame and 26 ms per Viewer frame. So Helm's per-frame script and engine work is about three times Viewer's, and it does not depend on the GPU. Graphics: Low and the 30 fps cap change nothing here. Low only drops ship materials, and the cap only acts above 30 fps.

**Audio.** Audio runs on the main thread (R21-2), so it breaks up whenever a frame takes longer than about 85 ms (two 42.7 ms buffers). Every Helm run starved 47-85 % of the time. Only the tiny-canvas Viewer runs, at 75-124 ms p95, came close to continuous sound (0-8 %). The long frames at join (1-4 s) will crackle on any phone.

**Memory.** The wasm heap is 190 MB in every run. The JS heap is 57-128 MB (it depends on when the GC last ran). The page's renderer process uses 480-560 MB PSS, which fits a 4 GB phone such as the Galaxy S8. The GPU process (here SwiftShader, 170-260 MB) is not comparable to a phone.

**Snapshots.** The server saw the page's snapshot age at 400-800 ms (p50), because the page reads the socket once a frame. It follows the frame rate.

## Caveats

- Headless Chromium renders WebGL with SwiftShader, on the CPU. Frame times at full size are pessimistic for any phone with a GPU, so the first table's fps, frame times and audio figures are not a phone's. SwiftShader shared CPUs 8-11 with the server, the stand-in crew and other sessions.
- CDP CPU throttling slows the renderer's main thread only. Wasm compilation, the GPU process and the network are not throttled. A 4x or 6x throttle of a fugaku core is a rough model of a cheap or old phone; a Pixel 7's big core is closer to 2x.
- Throttling also changes how CPU time is counted: under it the main thread's CPU time is close to the frame time, so the per-frame main-thread cost is estimated as the throttled cost divided by the factor.
- The tiny-canvas pass changes the canvas size that Godot lays out in, so it is not the same picture. It removes most of the GPU cost; it does not remove all of it (Helm still used about 500 ms of SwiftShader CPU per frame).
- The phone did not steer or fire. The stand-in crew steered and fired on every ship, and the raiders attacked.
- One run per row, under a host load average of 6-16; differences of 10-20 % between rows are noise.
- Not measured headlessly: real audio crackles (there is no speaker; the starvation figure is an estimate from callback timing), touch latency, heat and battery, and Safari on iOS.

## Files

The scripts (`measure_phone.js` runs one case), the raw runs and the export are on fugaku in `~/.local/state/full-theta/night-2026-11-15/phone/`, outside the repository.
