import { test, expect } from "@playwright/test";
import * as fs from "fs";

const manifestPath = process.env.MANIFEST_PATH ?? "dashboard.config.json";
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
const charts: { id: string; title: string }[] = manifest.charts;

test("page loads with HTTP 200", async ({ page }) => {
    const response = await page.goto("/");
    expect(response?.status()).toBe(200);
});

test("page title matches manifest", async ({ page }) => {
    await page.goto("/");
    const title = await page.title();
    expect(title.trim().length).toBeGreaterThan(0);
    expect(title).toContain(manifest.title.split(",")[0].trim());
});

test("no console errors on load", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
    });
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(errors, `console errors: ${errors.join("; ")}`).toHaveLength(0);
});

for (const chart of charts) {
    test(`chart "${chart.id}" renders with SVG content`, async ({ page }) => {
        await page.goto("/");

        const mount = page.locator(`#chart-${chart.id}`);
        await expect(mount).toBeVisible();

        await expect(mount).toHaveAttribute("data-plotly-rendered", "true", {
            timeout: 10_000,
        });

        const errorAttr = await mount.getAttribute("data-plotly-error");
        expect(
            errorAttr,
            `chart ${chart.id} reported a render error: ${errorAttr}`
        ).toBeNull();

        const svg = mount.locator("svg").first();
        await expect(svg).toBeVisible();

        const childCount = await svg.locator("> *").count();
        expect(
            childCount,
            `chart ${chart.id} SVG appears empty`
        ).toBeGreaterThan(0);
    });
}
