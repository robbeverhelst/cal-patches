// Capture the booker of the seeded dummy event at desktop and mobile width.
//   node capture.mjs <label> <outDir> <booked YYYY-MM-DD> <blocked YYYY-MM-DD> <expectBusy 0|1>
import { mkdir, writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const [label, outDir, booked, blocked, expectBusy] = process.argv.slice(2);
const base = "http://localhost:3000/demo/afspraak";
const viewports = {
  desktop: { width: 1440, height: 900 },
  mobile: { width: 390, height: 844 },
};
const shots = [
  { name: "month-booked-day", query: { month: booked.slice(0, 7), date: booked } },
  { name: "month-blocked-day", query: { month: blocked.slice(0, 7), date: blocked } },
  { name: "week", query: { layout: "week_view", month: booked.slice(0, 7), date: booked }, desktopOnly: true },
];

await mkdir(outDir, { recursive: true });
const browser = await chromium.launch();
const busyCounts = {};
for (const [viewport, size] of Object.entries(viewports)) {
  const context = await browser.newContext({
    viewport: size,
    deviceScaleFactor: viewport === "mobile" ? 2 : 1,
    locale: "nl-BE",
    timezoneId: "Europe/Brussels",
  });
  for (const shot of shots) {
    if (shot.desktopOnly && viewport !== "desktop") continue;
    const page = await context.newPage();
    // Keep the slots responses next to the shots, to tell a server problem from a UI one.
    const responses = [];
    page.on("response", async (response) => {
      if (!response.url().includes("getSchedule")) return;
      responses.push({ url: response.url(), status: response.status(), body: await response.text().catch(() => "") });
    });
    await page.goto(`${base}?${new URLSearchParams(shot.query)}`, { waitUntil: "networkidle", timeout: 120_000 });
    if (!shot.query.layout) {
      await page
        .waitForSelector('[data-testid="time"], [data-testid="no-slots-available"]', { timeout: 60_000 })
        .catch(() => console.warn(`${label} ${viewport} ${shot.name}: no time list rendered`));
    }
    await page.waitForTimeout(1500);
    busyCounts[`${viewport}/${shot.name}`] = await page.locator("[data-busy]").count();
    const file = `${outDir}/${label}-${viewport}-${shot.name}.png`;
    await page.screenshot({ path: file, fullPage: true });
    await writeFile(file.replace(/\.png$/, ".slots.json"), JSON.stringify(responses, null, 1));
    console.log(`${file} (busy slots on page: ${busyCounts[`${viewport}/${shot.name}`]})`);
    await page.close();
  }
  await context.close();
}
await browser.close();

const sawBusy = busyCounts["desktop/month-booked-day"] > 0 && busyCounts["desktop/month-blocked-day"] > 0;
if (expectBusy === "1" && !sawBusy) {
  console.error(`${label}: expected busy slots on the booked and the blocked day`, busyCounts);
  process.exit(1);
}
if (expectBusy === "0" && Object.values(busyCounts).some((n) => n > 0)) {
  console.error(`${label}: expected no busy slots`, busyCounts);
  process.exit(1);
}
