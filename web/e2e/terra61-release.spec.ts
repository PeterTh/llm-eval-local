import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "gpt-6.1-terra-medium";
const batch = "20261028-200951";
const original = "c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36";
const corrected = "6e8d51b08ba6dd1a9bf75a659920c05831829bec";

test("Terra timing correction retains both source versions and native evidence", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const id = `qtclustering_${model}_mpi_r1`;
  await page.goto(`${basePath}#/run/${id}?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`${original}/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`${corrected}/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/benchmark/records`));
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await page.screenshot({ path: testInfo.outputPath("terra61-corrected-run.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Terra cost and generation time use complete native accounting", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row).toContainText("GPT-6.1 Terra Medium");
  await expect(row.getByRole("cell", { name: "$0.0217", exact: true })).toBeVisible();
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://developers.openai.com/api/docs/models/gpt-6.1-terra");
  const costPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const costDownload = await costPromise;
  const costs = parse(await readFile((await costDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(costs).toHaveLength(1);
  expect(Number(costs[0]!.estimated_mean_cost_usd)).toBeCloseTo(4.7754273 / 220, 10);
  await page.screenshot({ path: testInfo.outputPath("terra61-cost.png"), fullPage: true });

  await page.goto(`${basePath}#/time?model=${model}`);
  await expect(page.locator(".time_points path")).toHaveCount(1);
  const timePromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const timeDownload = await timePromise;
  const times = parse(await readFile((await timeDownload.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(times).toHaveLength(1);
  expect(Number(times[0]!.time_run_count)).toBe(220);
  expect(Number(times[0]!.recovered_time_run_count)).toBe(0);
  expect(Number(times[0]!.mean_generation_seconds)).toBeCloseTo(16047.94 / 220, 8);
});

test("Terra uses the shared Codex methodology record", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/methodology`);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Codex CLI", exact: true }) });
  await expect(harness.getByText("GPT-6.1 Terra Medium", { exact: true })).toHaveAttribute("title", /invoked model gpt-6\.1-terra; reasoning effort medium/);
  await expect(page.getByRole("heading", { name: "OpenCode", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("terra61-methodology.png"), fullPage: true });
});
