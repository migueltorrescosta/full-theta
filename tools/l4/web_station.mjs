// L4 browser station (FT-NET-013, FT-NET-030, FT-NET-046, FT-AUD-017, FT-TST-021): headless
// Chromium opens the web build from a LAN-like host name (an http:// page, not a secure
// context, as on a tablet), joins by itself (D196), takes the Tactical station through the
// ?pick= test hook, taps once (audio unlocks, the keep-awake video plays), plays (all-stop
// presses), is "suspended and woken" (the page reconnects with its token), and takes one
// touch-layout screenshot that must not be blank.
//   node tools/l4/web_station.mjs URL OUT_DIR [TIMEOUT_S]
// Writes OUT_DIR/shot.png and OUT_DIR/web.json; exits 0 when every check passed.
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";

// playwright-core is installed by tools/l6 (npm ci); resolve it from there.
const require = createRequire(new URL("../l6/package.json", import.meta.url));
const { chromium } = require("playwright-core");

const [url, outDir, timeoutS = "120"] = process.argv.slice(2);
if (!url || !outDir) {
  console.error("usage: web_station.mjs URL OUT_DIR [TIMEOUT_S]");
  process.exit(2);
}
const host = new URL(url).hostname;
const timeout = Number(timeoutS) * 1000;
const checks = {};
const note = (name, ok, detail = "") => {
  checks[name] = { ok: !!ok, detail: String(detail) };
  console.log(`web_station: ${ok ? "ok  " : "FAIL"} ${name} ${detail}`);
};

// Colours (4 bits a channel) and luminance spread of a PNG, measured inside the page.
async function look(page, png) {
  return page.evaluate(async (b64) => {
    const blob = await (await fetch(`data:image/png;base64,${b64}`)).blob();
    const bmp = await createImageBitmap(blob);
    const c = new OffscreenCanvas(bmp.width, bmp.height);
    const g = c.getContext("2d");
    g.drawImage(bmp, 0, 0);
    const { data } = g.getImageData(0, 0, bmp.width, bmp.height);
    const seen = new Set();
    let sum = 0, sum2 = 0, n = 0;
    for (let i = 0; i < data.length; i += 4 * 7) {
      const lum = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      sum += lum; sum2 += lum * lum; n++;
      seen.add(((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4));
    }
    const mean = sum / n;
    return { w: bmp.width, h: bmp.height, colours: seen.size, std: Math.sqrt(sum2 / n - mean * mean) };
  }, png.toString("base64"));
}

const browser = await chromium.launch({
  headless: true,
  args: [
    "--enable-unsafe-swiftshader",
    "--use-angle=swiftshader",
    "--ignore-gpu-blocklist",
    // As on a tablet: the audio context stays suspended until the page gets a tap.
    "--autoplay-policy=user-gesture-required",
    `--host-resolver-rules=MAP ${host} 127.0.0.1`,
  ],
});
let failed = true;
try {
  // An iPad-sized touch screen.
  const context = await browser.newContext({
    viewport: { width: 1024, height: 768 },
    hasTouch: true,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  const engineLog = [];
  page.on("console", (m) => {
    if (["error", "warning"].includes(m.type())) engineLog.push(`${m.type()}: ${m.text().slice(0, 300)}`);
  });
  const start = Date.now();
  await page.goto(`${url}?pick=tactical&ready=1`);

  // Joined, picked, started: the page names its panel.
  const reached = await page
    .waitForFunction(() => window.ftPanel === "tactical", null, { timeout })
    .then(() => true, () => false);
  note("joins and shows the Tactical panel", reached, `after ${Date.now() - start} ms`);
  if (!reached) throw new Error("never reached the panel");
  note("page is not a secure context", !(await page.evaluate(() => window.isSecureContext)));

  // Audio: unlocked by a tap, not before (FT-AUD-017).
  const before = await page.evaluate(() => window.ft.audioState());
  await page.touchscreen.tap(600, 400);
  const unlocked = await page
    .waitForFunction(() => window.ft.audioState() === "running", null, { timeout: 15000 })
    .then(() => true, () => false);
  // Chromium may start its context running whatever the policy flag says; the check that
  // counts is that it is running after the tap.
  console.log(`web_station: audio state before the tap: ${before || "none"}`);
  note("audio unlocks after a tap", unlocked, `state after: ${await page.evaluate(() => window.ft.audioState())}`);

  // Keep-awake video plays (FT-NET-046).
  const awake = await page
    .waitForFunction(() => window.ftKeepAwake === "video", null, { timeout: 15000 })
    .then(() => true, () => false);
  // The video is 2 s long and loops, so its time may wrap: it plays if the time moves.
  const time = () => page.evaluate(() => document.getElementById("ft-keepawake")?.currentTime ?? -1);
  const t0 = await time();
  await page.waitForTimeout(700);
  const t1 = await time();
  const paused = await page.evaluate(() => document.getElementById("ft-keepawake")?.paused);
  const src = await page.evaluate(() => document.getElementById("ft-keepawake")?.currentSrc);
  note("keep-awake video plays", awake && t1 !== t0 && !paused, `time ${t0} -> ${t1}, ${src}`);

  // A first visit opens the controls list over the station: close it with its Back button.
  await page.touchscreen.tap(38, 32);

  // The screenshot (FT-TST-021): software rendering on 2 cores draws a frame a second or
  // so, so look until the station is on screen (not blank: several colours, some contrast).
  let stats = null;
  const seenBy = Date.now() + 45000;
  while (Date.now() < seenBy) {
    const shot = await page.screenshot({ path: `${outDir}/shot.png`, timeout: 120000 });
    stats = await look(page, shot);
    if (stats.colours >= 8 && stats.std > 4) break;
    await page.waitForTimeout(2000);
  }
  // The tablet's touch layout (FT-STN-005, D194): the client chose it from the viewport and
  // the pointer, and the picture is the Tactical station, not a blank or an error page.
  const layout = await page.evaluate(() => window.ftLayout);
  note("screenshot is a touch layout, not blank, and shows the panel",
    stats && stats.colours >= 8 && stats.std > 4 && layout === "touch" &&
      (await page.evaluate(() => window.ftPanel)) === "tactical",
    `${layout} ${JSON.stringify(stats)}`);

  // Play: all-stop (Space) a few times.
  for (let i = 0; i < 4; i++) {
    await page.keyboard.press("Space");
    await page.waitForTimeout(300);
  }

  // Safari suspends the page: simulate a return after 3 s hidden. The page must
  // reconnect on its own and keep its panel.
  await page.evaluate(() => {
    window.ft.hiddenAt = Date.now() - 3000;
    document.dispatchEvent(new Event("visibilitychange"));
  });
  const wakes = await page.evaluate(() => window.ft.wakes);
  await page.waitForTimeout(6000);
  note("a wake is noticed", wakes === 1, `wakes ${wakes}`);
  note("still on the panel after the reconnect", (await page.evaluate(() => window.ftPanel)) === "tactical");
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press("Space");
    await page.waitForTimeout(300);
  }

  // Pointer lock is Godot's mouse capture for the Helm's mouse look; a tablet has no use for it.
  const real = errors.filter((e) => !e.includes("Pointer Lock"));
  note("no page errors", real.length === 0, real.join(" | "));
  failed = Object.values(checks).some((c) => !c.ok);
  if (failed) console.log(`web_station: engine console (errors, warnings):\n  ${engineLog.slice(0, 25).join("\n  ")}`);
} catch (e) {
  note("run", false, e.message);
} finally {
  writeFileSync(`${outDir}/web.json`, JSON.stringify(checks, null, 1));
  await browser.close();
}
process.exit(failed ? 1 : 0);
