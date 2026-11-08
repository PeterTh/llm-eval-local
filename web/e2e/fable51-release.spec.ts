import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "claude-fable-5.1-cc-medium";
const batch = "20261011-092100";

test("Fable winners expose concise group reviews and the outlier caveat", async ({ page }, testInfo) => {
  for (const [benchmark, backend] of [["nbody", "omp"], ["qtclustering", "omp"], ["cholesky", "hybrid"]]) {
    await page.goto(`${basePath}#/run/${benchmark}_${model}_${backend}_r4?model-set=all`);
    await expect(page.getByRole("heading", { name: "Finding", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Close-group comparison", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Interpretation", exact: true })).toBeVisible();
  }
  await expect(page.getByText(/cannot be interpreted as an end-to-end host-result speedup/)).toBeVisible();
  await expect(page.getByRole("link", { name: "limited diagnostic", exact: true })).toHaveAttribute("href", /2026-11-08-fable51-outlier-probes.json$/);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("fable51-winner-review.png"), fullPage: true });
});

test("Fable timing correction retains both source versions and native evidence", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const id = `roomsim_${model}_hybrid_r2`;
  await page.goto(`${basePath}#/run/${id}?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`e3a476e84284ddea4052c6e55e92439f10f38b1a/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`cae4e2e3f5e18f26b9465db9f9a84e1593064e65/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/benchmark/records`));
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await page.screenshot({ path: testInfo.outputPath("fable51-corrected-run.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Fable cost and generation duration use accepted native attempts", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row).toContainText("Fable 5.1 Medium");
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://platform.claude.com/docs/en/models/fable-5-1/overview");
  const costPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const costDownload = await costPromise;
  const costs = parse(await readFile((await costDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(costs).toHaveLength(1);
  expect(Number(costs[0]!.estimated_mean_cost_usd)).toBeCloseTo(844.63326075 / 220, 10);
  expect(Number(costs[0]!.recorded_usage_lower_bound_run_count)).toBe(0);
  await page.screenshot({ path: testInfo.outputPath("fable51-cost.png"), fullPage: true });

  await page.goto(`${basePath}#/time?model=${model}`);
  await expect(page.locator(".time_points path")).toHaveCount(1);
  const timePromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const timeDownload = await timePromise;
  const times = parse(await readFile((await timeDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(times).toHaveLength(1);
  expect(Number(times[0]!.time_run_count)).toBe(220);
  expect(Number(times[0]!.recovered_time_run_count)).toBe(0);
  expect(Number(times[0]!.mean_generation_seconds)).toBeCloseTo(325886.43 / 220, 8);
  await page.screenshot({ path: testInfo.outputPath("fable51-time.png"), fullPage: true });
});

test("Fable joins the single shared Claude Code methodology record", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/methodology`);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Claude Code", exact: true }) });
  await expect(harness.locator(".harness-models > span")).toHaveCount(7);
  await expect(harness.getByText("Fable 5.1 Medium", { exact: true })).toHaveAttribute("title", /invoked model claude-fable-5-1; reasoning effort medium/);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("fable51-methodology.png"), fullPage: true });
});
