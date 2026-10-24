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

const browser = await chromium.launch({
  headless: true,
  args: [
    "--enable-unsafe-swiftshader",
    "--use-angle=swiftshader",
    "--ignore-gpu-blocklist",
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
  await page.touchscreen.tap(512, 400);
  const unlocked = await page
    .waitForFunction(() => window.ft.audioState() === "running", null, { timeout: 15000 })
    .then(() => true, () => false);
  note("audio unlocks after a tap", unlocked, `state before the tap: ${before || "none"}`);

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

  // The screenshot: not blank, the panel's top bar region is drawn.
  const shot = await page.screenshot({ path: `${outDir}/shot.png` });
  const stats = await page.evaluate(async (b64) => {
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
  }, shot.toString("base64"));
  note("screenshot is not blank", stats.colours >= 8 && stats.std > 4, JSON.stringify(stats));
  // Pointer lock is Godot's mouse capture for the Helm's mouse look; a tablet has no use for it.
  const real = errors.filter((e) => !e.includes("Pointer Lock"));
  note("no page errors", real.length === 0, real.join(" | "));
  failed = Object.values(checks).some((c) => !c.ok);
} catch (e) {
  note("run", false, e.message);
} finally {
  writeFileSync(`${outDir}/web.json`, JSON.stringify(checks, null, 1));
  await browser.close();
}
process.exit(failed ? 1 : 0);
