// S3 browser harness (T021, TECH-3): drives the web export in headless
// Chromium (SwiftShader WebGL) through Playwright and writes a JSON result.
//   node harness.mjs MODE --url http://s3.lan:47820/ --out result.json [flags]
// Modes:
//   join     load, join, keep 30 s for fps, tap for audio, press "+" once
//   refresh  join, then reload --reloads N times and time each rejoin
//   idle     join, tap (starts the keep-awake), idle --minutes M, check the socket
//   multi    --clients N fresh browser contexts load and join at once
// Flags: --fps-seconds [30] --reloads [10] --minutes [10] --clients [6]
//   --timeout-s [60] --viewport 1280x800 --mbps [0 = loopback speed]
// --mbps throttles each page's HTTP to that many Mbit/s down (a fifth of it
// up) with 5 ms added latency, through the DevTools protocol, as a rough
// stand-in for a tablet on Wi-Fi.
// Every page runs with touch (a tablet-sized viewport) and the default
// autoplay policy, so audio needs a tap.
import { chromium } from "playwright-core";
import { writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const mode = args[0];
const opt = (name, dflt) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : dflt;
};
const url = opt("url", "http://s3.lan:47820/");
const out = opt("out", `s3-${mode}.json`);
const timeoutMs = Number(opt("timeout-s", "60")) * 1000;
const [vw, vh] = opt("viewport", "1280x800").split("x").map(Number);
const mbps = Number(opt("mbps", "0"));

// Wraps Web Audio before the page runs: every node connected to the
// destination goes through an analyser, and a timer keeps the peak level, so
// the harness can tell that sound reached the output.
const AUDIO_PROBE = `(() => {
  const ctxs = [];
  const probe = { ctxs, peak: 0, connects: 0, created: 0 };
  window.__s3audio = probe;
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    if (dest instanceof AudioDestinationNode) {
      const ctx = dest.context;
      if (!ctx.__s3an) {
        ctx.__s3an = ctx.createAnalyser();
        ctx.__s3an.fftSize = 2048;
        connect.call(ctx.__s3an, dest);
      }
      if (!ctxs.includes(ctx)) ctxs.push(ctx);
      probe.connects++;
      return connect.call(this, ctx.__s3an, ...rest);
    }
    return connect.call(this, dest, ...rest);
  };
  const Base = window.AudioContext;
  window.AudioContext = class extends Base {
    constructor(...a) { super(...a); probe.created++; ctxs.push(this); }
  };
  const buf = new Float32Array(2048);
  setInterval(() => {
    for (const ctx of ctxs) {
      if (!ctx.__s3an) continue;
      ctx.__s3an.getFloatTimeDomainData(buf);
      for (const x of buf) if (Math.abs(x) > probe.peak) probe.peak = Math.abs(x);
    }
  }, 20);
  window.__s3audioState = () => ({
    states: ctxs.map((c) => c.state), peak: probe.peak,
    connects: probe.connects, created: probe.created });
})();`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const LAUNCH = {
  headless: true,
  args: [
    "--enable-unsafe-swiftshader",
    "--use-angle=swiftshader",
    "--ignore-gpu-blocklist",
    // A LAN-like host name: 127.0.0.1 and localhost count as secure contexts.
    "--host-resolver-rules=MAP s3.lan 127.0.0.1",
  ],
};
const CONTEXT = { viewport: { width: vw, height: vh }, hasTouch: true };

// --profile DIR gives one persistent context with a disk cache, as a tablet
// browser has. Playwright's default contexts keep an in-memory cache that
// doesn't hold the 10 MB wasm, so every reload downloads it again.
async function launch() {
  const profile = opt("profile", "");
  if (!profile) return chromium.launch(LAUNCH);
  const context = await chromium.launchPersistentContext(profile, { ...LAUNCH, ...CONTEXT });
  return { newContext: async () => context, close: () => context.close() };
}

// One station page with its console log of "S3 <kind> <json>" lines.
async function openStation(browser, name) {
  const context = await browser.newContext(CONTEXT);
  await context.addInitScript(AUDIO_PROBE);
  const page = await context.newPage();
  if (mbps > 0) {
    const cdp = await context.newCDPSession(page);
    await cdp.send("Network.enable");
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false,
      latency: 5,
      downloadThroughput: (mbps * 1e6) / 8,
      uploadThroughput: (mbps * 1e6) / 40,
    });
  }
  const st = { name, context, page, log: [], errors: [] };
  page.on("console", (msg) => {
    const text = msg.text();
    if (!text.startsWith("S3 ")) return;
    const sp = text.indexOf(" ", 3);
    const kind = text.slice(3, sp);
    let data = {};
    try {
      data = JSON.parse(text.slice(sp + 1));
    } catch {
      data = { raw: text };
    }
    st.log.push({ t: Date.now(), kind, data });
  });
  page.on("pageerror", (e) => st.errors.push(String(e)));
  page.on("crash", () => st.errors.push("crash"));
  return st;
}

// Waits for a log entry after index `from` that matches; returns it.
async function waitFor(st, kind, from = 0, pred = () => true, ms = timeoutMs) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    for (let i = from; i < st.log.length; i++) {
      if (st.log[i].kind === kind && pred(st.log[i].data)) return st.log[i];
    }
    await sleep(10);
  }
  throw new Error(`${st.name}: timed out waiting for ${kind}`);
}

// Navigates and returns the join times: page_ms is performance.now() at the
// first applied snapshot (navigation start to snapshot), node_ms the same seen
// from the harness.
async function join(st, query) {
  const t0 = Date.now();
  await st.page.goto(url + query, { waitUntil: "commit", timeout: timeoutMs });
  const first = await waitFor(st, "first_snapshot");
  const welcome = await waitFor(st, "welcome");
  return {
    page_ms: first.data.page_ms,
    node_ms: first.t - t0,
    seat: welcome.data.seat,
    resumed: welcome.data.resumed,
  };
}

function fpsStats(st, fromT, toT) {
  const v = st.log.filter((e) => e.kind === "fps" && e.t >= fromT && e.t <= toT)
    .map((e) => e.data.fps);
  if (!v.length) return { n: 0 };
  const s = [...v].sort((a, b) => a - b);
  return { n: v.length, mean: v.reduce((a, b) => a + b, 0) / v.length, min: s[0],
    p10: s[Math.floor(s.length * 0.1)], max: s[s.length - 1] };
}

async function layout(st) {
  return (await waitFor(st, "layout")).data;
}

// Taps the audio button; returns audio state before and after the clip.
async function tapAudio(st) {
  const lay = await layout(st);
  const before = await st.page.evaluate(() => window.__s3audioState());
  const from = st.log.length;
  const t0 = Date.now();
  await st.page.touchscreen.tap(lay.tap[0], lay.tap[1]);
  const tap = await waitFor(st, "tap", from);
  const play = await waitFor(st, "voice_play", from);
  let done = null;
  try {
    done = await waitFor(st, "voice_done", from, () => true, 5000);
  } catch {
    done = null;
  }
  const after = await st.page.evaluate(() => window.__s3audioState());
  return {
    before, after,
    tap_to_voice_ms: play.t - t0,
    sha_ok: play.data.sha_ok,
    clip_bytes: play.data.bytes,
    finished: done !== null,
    keep_awake: tap.data.keep_awake,
  };
}

async function pressPlus(st, system) {
  const lay = await layout(st);
  const from = st.log.length;
  const [x, y] = lay.plus[system];
  await st.page.touchscreen.tap(x, y);
  const applied = await waitFor(st, "cmd_applied", from, (d) => d.sys === system, 5000)
    .catch(() => null);
  return applied ? applied.data : null;
}

async function modeJoin(browser) {
  const st = await openStation(browser, "j0");
  const j = await join(st, "?name=j0");
  const fpsSeconds = Number(opt("fps-seconds", "30"));
  const t0 = Date.now();
  await sleep(fpsSeconds * 1000);
  const fps = fpsStats(st, t0 + 1000, Date.now());
  const audio = await tapAudio(st);
  const cmd = await pressPlus(st, 0);
  const keepAwake = await st.page.evaluate(() => window.ftKeepAwake || "off");
  return { join: j, fps, audio, cmd, keep_awake: keepAwake, errors: st.errors };
}

async function modeRefresh(browser) {
  const st = await openStation(browser, "r0");
  const first = await join(st, "?name=r0");
  await sleep(2000);
  const reloads = Number(opt("reloads", "10"));
  const runs = [];
  for (let i = 0; i < reloads; i++) {
    const from = st.log.length;
    const t0 = Date.now();
    await st.page.reload({ waitUntil: "commit", timeout: timeoutMs });
    const w = await waitFor(st, "welcome", from);
    const s = await waitFor(st, "first_snapshot", from);
    const boot = await waitFor(st, "boot", from);
    runs.push({
      reload_to_snapshot_ms: s.t - t0,
      page_ms: s.data.page_ms,
      boot_page_ms: boot.data.page_ms,
      welcome_page_ms: w.data.page_ms,
      resumed: w.data.resumed,
      same_seat: JSON.stringify(w.data.seat) === JSON.stringify(first.seat),
    });
    await sleep(3000);
  }
  const v = runs.map((r) => r.reload_to_snapshot_ms);
  return {
    first, runs,
    mean_ms: v.reduce((a, b) => a + b, 0) / v.length,
    max_ms: Math.max(...v),
    all_resumed: runs.every((r) => r.resumed && r.same_seat),
    errors: st.errors,
  };
}

async function modeIdle(browser) {
  const st = await openStation(browser, "i0");
  const j = await join(st, "?name=i0");
  const audio = await tapAudio(st);
  const minutes = Number(opt("minutes", "10"));
  const t0 = Date.now();
  const samples = [];
  while (Date.now() - t0 < minutes * 60000) {
    await sleep(30000);
    const s = await st.page.evaluate(() => {
      const v = document.getElementById("ft-keepawake");
      return { playing: v ? !v.paused : false, time: v ? v.currentTime : -1,
        mode: window.ftKeepAwake || "off", hidden: document.hidden };
    });
    s.at_s = Math.round((Date.now() - t0) / 1000);
    samples.push(s);
  }
  const statuses = st.log.filter((e) => e.kind === "status" && e.t >= t0);
  const closed = st.log.filter((e) => e.kind === "closed");
  const lastStatus = statuses.at(-1);
  return {
    join: j, audio, minutes, samples,
    closed: closed.length,
    status_lines: statuses.length,
    all_open: statuses.every((e) => e.data.open),
    last_status: lastStatus ? lastStatus.data : null,
    video_always_playing: samples.every((s) => s.playing),
    errors: st.errors,
  };
}

async function modeMulti(browser) {
  const n = Number(opt("clients", "6"));
  const stations = [];
  for (let i = 0; i < n; i++) stations.push(await openStation(browser, `m${i}`));
  const t0 = Date.now();
  const joins = await Promise.all(stations.map((st) => join(st, `?name=${st.name}`)
    .catch((e) => ({ error: String(e) }))));
  const tJoined = Date.now();
  const fpsSeconds = Number(opt("fps-seconds", "30"));
  await sleep(fpsSeconds * 1000);
  const fps = stations.map((st) => fpsStats(st, tJoined + 1000, Date.now()));
  const v = joins.filter((j) => j.node_ms).map((j) => j.node_ms);
  return {
    clients: n, started_unix_ms: t0, all_joined_unix_ms: tJoined,
    joins, join_max_ms: Math.max(...v), join_mean_ms: v.reduce((a, b) => a + b, 0) / v.length,
    fps, errors: stations.flatMap((st) => st.errors),
  };
}

const modes = { join: modeJoin, refresh: modeRefresh, idle: modeIdle, multi: modeMulti };
if (!modes[mode]) {
  console.error(`unknown mode ${mode}; use ${Object.keys(modes).join(", ")}`);
  process.exit(2);
}
const browser = await launch();
let result;
try {
  result = {
    mode, url, mbps, started: new Date().toISOString(), ...(await modes[mode](browser)),
  };
} catch (e) {
  result = { mode, url, error: String(e.stack || e) };
}
await browser.close();
writeFileSync(out, JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2).slice(0, 4000));
process.exit(result.error ? 1 : 0);
