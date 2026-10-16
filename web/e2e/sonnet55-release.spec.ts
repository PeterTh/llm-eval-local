import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "claude-sonnet-5.5-cc-medium";
const originalCommit = "8fe249fe2622f21b32faf8d13cd290ce902f78cd";
const correctedCommit = "6196b2ba8d2509ff0a7ba87d17d846a479a39282";

test("Sonnet timing correction retains both sources and benchmark evidence", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(basePath + `#/run/black-scholes_${model}_hybrid_r1?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByText("Successful benchmark execution.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit + "/20261014-212207/"));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(correctedCommit + "/20261014-212207/"));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", /batches\/20261014-212207\/benchmark\/records/);
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await expect(page.getByText("Recovered generation duration.", { exact: true })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("sonnet55-corrected-run.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Sonnet native validation failure stays unbenchmarked", async ({ page }) => {
  await page.goto(basePath + `#/run/nbody_${model}_mpi_r1?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
});

test("Sonnet recovered generation duration is qualified and exported", async ({ page }, testInfo) => {
  const id = `qtclustering_${model}_omp_r2`;
  await page.goto(basePath + `#/run/${id}?model-set=all`);
  await expect(page.getByRole("heading", { name: "14.42 min generation time", exact: true })).toBeVisible();
  await expect(page.getByText("Recovered generation duration.", { exact: true })).toBeVisible();
  await expect(page.getByText(/It excludes wrapper setup and teardown; the wrapper exit status is unknown/)).toBeVisible();
  await expect(page.getByRole("link", { name: /Recovery evidence/ })).toHaveAttribute("href", new RegExp(`batches/20261014-212207/generation/recoveries/${id}\\.json$`));
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit));
  await page.screenshot({ path: testInfo.outputPath("sonnet55-recovered-duration.png"), fullPage: true });

  await page.goto(basePath + `#/time?model=${model}`);
  await expect(page.locator(".time_points path")).toHaveCount(1);
  await expect(page.getByText(/Includes 1 recovered native generation duration, excluding wrapper setup and teardown/)).toBeVisible();
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const download = await downloadPromise;
  const rows = parse(await readFile((await download.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(rows).toHaveLength(1);
  expect(rows[0].model).toBe(model);
  expect(Number(rows[0].time_run_count)).toBe(220);
  expect(Number(rows[0].recovered_time_run_count)).toBe(1);
  expect(Number(rows[0].mean_generation_seconds)).toBeCloseTo(46457.999 / 220, 8);
  await page.screenshot({ path: testInfo.outputPath("sonnet55-time.png"), fullPage: true });
});

test("Sonnet flat pricing and the shared Claude harness are visible", async ({ page }, testInfo) => {
  await page.goto(basePath + `#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row).toContainText("Sonnet 5.5 Medium");
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://platform.claude.com/docs/en/models/sonnet-5-5/overview");
  await page.screenshot({ path: testInfo.outputPath("sonnet55-cost.png"), fullPage: true });
  await page.goto(basePath + "#/methodology");
  await expect(page.getByRole("heading", { name: /^Claude Code/ })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Claude Code", exact: true }) });
  await expect(harness.locator(".harness-models > span")).toHaveCount(6);
  await expect(harness.getByText("Sonnet 5.5 Medium", { exact: true })).toHaveAttribute("title", /invoked model claude-sonnet-5-5; reasoning effort medium/);
  await page.screenshot({ path: testInfo.outputPath("sonnet55-methodology.png"), fullPage: true });
});
