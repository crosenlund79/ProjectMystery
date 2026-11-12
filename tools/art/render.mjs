// Renders SVG drawings to PNG with the browser that ships with Playwright.
//
//   node tools/art/render.mjs <manifest.json>
//
// The manifest is a JSON list of {"out": "<png path>", "w": <width>, "h": <height>, "svg": "<svg markup>"}
// written by tools/art/make_art.py. Transparent where the drawing is transparent.
import { readFileSync } from "node:fs";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require("playwright");
} catch {
  playwright = require(require.resolve("playwright", { paths: [process.cwd(), "/usr/lib/node_modules", "/usr/local/lib/node_modules"] }));
}

const jobs = JSON.parse(readFileSync(process.argv[2], "utf8"));
const browser = await playwright.chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
let done = 0;
for (const job of jobs) {
  mkdirSync(dirname(job.out), { recursive: true });
  await page.setViewportSize({ width: job.w, height: job.h });
  await page.setContent(
    `<!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent}svg{display:block}</style></head>` +
      `<body>${job.svg}</body></html>`
  );
  await page.locator("svg").first().screenshot({ path: job.out, omitBackground: true });
  done += 1;
}
await browser.close();
console.log(`rendered ${done} image(s)`);
