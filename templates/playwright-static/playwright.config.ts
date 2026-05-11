import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
    testDir: "./tests",
    fullyParallel: false,
    retries: 0,
    workers: 1,
    reporter: [
        ["list"],
        ["json", { outputFile: "test-results/last-run.json" }],
    ],
    use: {
        baseURL: process.env.BASE_URL ?? "http://localhost:8080",
        headless: true,
        screenshot: "only-on-failure",
        video: "off",
        trace: "on-first-retry",
    },
    projects: [
        {
            name: "chromium",
            use: { ...devices["Desktop Chrome"] },
        },
    ],
    outputDir: "test-results",
});
