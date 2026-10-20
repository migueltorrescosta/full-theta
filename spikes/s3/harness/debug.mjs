// Loads the page for a few seconds and prints every console line and error,
// then saves a screenshot. node debug.mjs [SECONDS] [SHOT.png] [URL]
import { chromium } from "playwright-core";

const [seconds = "15", shot = "/tmp/s3-debug.png", url = "http://s3.lan:47820/?fresh=1"] =
  process.argv.slice(2);
const browser = await chromium.launch({
  headless: true,
  args: [
      "--enable-unsafe-swiftshader",
      "--use-angle=swiftshader",
      "--ignore-gpu-blocklist",
      // A LAN-like host name: 127.0.0.1 and localhost count as secure contexts.
      "--host-resolver-rules=MAP s3.lan 127.0.0.1",
    ],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const t0 = Date.now();
page.on("console", (m) => console.log(`${Date.now() - t0} [${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => console.log(`${Date.now() - t0} [pageerror] ${e} ${e.stack}`));
page.on("requestfailed", (r) => console.log(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`));
await page.goto(url);
await page.waitForTimeout(Number(seconds) * 1000);
await page.screenshot({ path: shot });
await browser.close();
