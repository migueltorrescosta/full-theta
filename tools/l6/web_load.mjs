// L6 web-export load check (FT-TST-019, D108): headless Chromium opens a
// package's bundled web export, served by the exported game's own HTTP server,
// from a LAN-like host name (not a secure context, as on a tablet), and waits
// for the engine to print the build line ReleaseBundle.build_line() prints.
//   node tools/l6/web_load.mjs URL EXPECTED_LINE [TIMEOUT_S]
// Exits 0 when the page printed EXPECTED_LINE with no page error, else 1.
import { chromium } from "playwright-core";

const [url, expected, timeoutS = "60"] = process.argv.slice(2);
if (!url || !expected) {
  console.error("usage: web_load.mjs URL EXPECTED_LINE [TIMEOUT_S]");
  process.exit(2);
}
const host = new URL(url).hostname;

const browser = await chromium.launch({
  headless: true,
  args: [
    "--enable-unsafe-swiftshader",
    "--use-angle=swiftshader",
    "--ignore-gpu-blocklist",
    // 127.0.0.1 and localhost count as secure contexts, which would hide the
    // http:// problems the custom shell and the index.js guard fix.
    `--host-resolver-rules=MAP ${host} 127.0.0.1`,
  ],
});
let code = 1;
try {
  const page = await browser.newPage();
  const errors = [];
  const lines = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  let seen;
  const printed = new Promise((resolve) => {
    seen = resolve;
  });
  page.on("console", (m) => {
    lines.push(m.text());
    if (m.text() === expected) seen();
  });
  const start = Date.now();
  await page.goto(url);
  const timer = new Promise((r) => setTimeout(r, Number(timeoutS) * 1000, "timeout"));
  const result = await Promise.race([printed.then(() => "ok"), timer]);
  const secure = await page.evaluate(() => window.isSecureContext);
  const ms = Date.now() - start;
  console.log(`web_load: ${url} ${result} after ${ms} ms, secure context ${secure}`);
  if (result !== "ok") console.log(`web_load: console was:\n  ${lines.join("\n  ")}`);
  for (const e of errors) console.log(`web_load: page error: ${e}`);
  code = result === "ok" && !secure && errors.length === 0 ? 0 : 1;
} finally {
  await browser.close();
}
process.exit(code);
