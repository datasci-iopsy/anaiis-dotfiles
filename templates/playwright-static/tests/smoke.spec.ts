import { test, expect } from "@playwright/test";

const selector = process.env.TEST_SELECTOR ?? "body";

test("page loads with HTTP 200", async ({ page }) => {
    const response = await page.goto("/");
    expect(response?.status()).toBe(200);
});

test("document title is non-empty", async ({ page }) => {
    await page.goto("/");
    const title = await page.title();
    expect(title.trim().length).toBeGreaterThan(0);
});

test("no console errors on load", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
    });
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    expect(errors).toHaveLength(0);
});

test("expected DOM node is present", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    const el = page.locator(selector).first();
    await expect(el).toBeVisible();
});
