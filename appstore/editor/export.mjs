// Headless "Export bundle" driver: clicks the editor's export and saves the zip.
import { chromium } from "playwright";
const out = process.argv[2] || "../export";
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
await p.goto("http://localhost:3001", { waitUntil: "networkidle" });
await p.getByRole("button", { name: "Export bundle" }).click();
const d = await p.waitForEvent("download", { timeout: 600000 });
await d.saveAs(`${out}/${d.suggestedFilename()}`);
console.log("saved", `${out}/${d.suggestedFilename()}`);
await b.close();
