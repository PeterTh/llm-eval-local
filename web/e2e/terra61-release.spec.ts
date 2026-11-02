import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const campaigns = [
  {
    effort: "medium", label: "GPT-6.1 Terra Medium", batch: "20261028-200951",
    original: "c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36",
    corrected: "6e8d51b08ba6dd1a9bf75a659920c05831829bec",
    totalCost: 4.7754273, displayedMeanCost: "$0.0217", generationSeconds: 16047.94,
  },
  {
    effort: "xhigh", label: "GPT-6.1 Terra XHigh", batch: "20261102-030935",
    original: "c070881d4b6186c32117ecd339e87d6f32db77e7",
    corrected: "db69dadaac5ae1d55b85e40af2cf6a59e07cf7e4",
    totalCost: 9.1368516, displayedMeanCost: "$0.0415", generationSeconds: 31943.98,
  },
];

for (const { effort, label, batch, original, corrected, totalCost, displayedMeanCost, generationSeconds } of campaigns) {
  const model = `gpt-6.1-terra-${effort}`;

  test(`Terra ${effort} timing correction retains both source versions and native evidence`, async ({ page }, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const id = `qtclustering_${model}_mpi_r1`;
    await page.goto(`${basePath}#/run/${id}?model-set=all`);
    await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`${original}/${batch}/${id}$`));
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`${corrected}/${batch}/${id}$`));
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/benchmark/records`));
    await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
    await page.screenshot({ path: testInfo.outputPath(`terra61-${effort}-corrected-run.png`), fullPage: true });
    expect(errors).toEqual([]);
  });

  test(`Terra ${effort} cost and generation time use complete native accounting`, async ({ page }, testInfo) => {
    await page.goto(`${basePath}#/cost?model=${model}`);
    await expect(page.locator(".cost_points path")).toHaveCount(1);
    await page.getByText("Accessible cost efficiency table", { exact: true }).click();
    const row = page.locator(".cost-data tbody tr");
    await expect(row).toHaveCount(1);
    await expect(row).toContainText(label);
    await expect(row.getByRole("cell", { name: displayedMeanCost, exact: true })).toBeVisible();
    await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://developers.openai.com/api/docs/models/gpt-6.1-terra");
    const costPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export", exact: true }).click();
    const costDownload = await costPromise;
    const costs = parse(await readFile((await costDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
    expect(costs).toHaveLength(1);
    expect(Number(costs[0]!.estimated_mean_cost_usd)).toBeCloseTo(totalCost / 220, 10);
    await page.screenshot({ path: testInfo.outputPath(`terra61-${effort}-cost.png`), fullPage: true });

    await page.goto(`${basePath}#/time?model=${model}`);
    await expect(page.locator(".time_points path")).toHaveCount(1);
    const timePromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export", exact: true }).click();
    const timeDownload = await timePromise;
    const times = parse(await readFile((await timeDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
    expect(times).toHaveLength(1);
    expect(Number(times[0]!.time_run_count)).toBe(220);
    expect(Number(times[0]!.recovered_time_run_count)).toBe(0);
    expect(Number(times[0]!.mean_generation_seconds)).toBeCloseTo(generationSeconds / 220, 8);
  });
}

test("Terra uses the shared Codex methodology record", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/methodology`);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Codex CLI", exact: true }) });
  for (const { effort, label } of campaigns) {
    await expect(harness.getByText(label, { exact: true })).toHaveAttribute("title", new RegExp(`invoked model gpt-6\\.1-terra; reasoning effort ${effort}`));
  }
  await expect(page.getByRole("heading", { name: "OpenCode", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("terra61-methodology.png"), fullPage: true });
});
