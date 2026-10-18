import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "gpt-6.1-sol-oc-medium";
const originalCommit = "352c09d57e14ef93744aa8cc741ff52884079e5f";
const correctedCommit = "9012afd8480bb000ff7b01581a91c6b680ef2394";

test("OpenCode corrected run retains both source revisions and exact token metadata", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(basePath + `#/run/roomsim_${model}_hybrid_r1?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByText("Successful benchmark execution.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit + "/20261017-192226/"));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(correctedCommit + "/20261017-192226/"));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", /batches\/20261017-192226\/benchmark\/records/);
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await expect(page.getByText("Recovered generation duration.", { exact: true })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("opencode-corrected-run.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("OpenCode ordinary validation failure is retained without benchmarking", async ({ page }) => {
  await page.goto(basePath + `#/run/matmul_${model}_mpi_r2?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
});

test("OpenCode time and cost remain separate from the native Sol profile", async ({ page }, testInfo) => {
  await page.goto(basePath + `#/time?model=${model}&model=gpt-6.1-sol-medium`);
  await expect(page.locator(".time_points path")).toHaveCount(2);
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const download = await downloadPromise;
  const rows = parse(await readFile((await download.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(rows).toHaveLength(2);
  const opencode = rows.find((row) => row.model === model)!;
  expect(Number(opencode.time_run_count)).toBe(220);
  expect(Number(opencode.recovered_time_run_count)).toBe(0);
  expect(Number(opencode.mean_generation_seconds)).toBeCloseTo(75839.228 / 220, 8);
  await page.screenshot({ path: testInfo.outputPath("opencode-native-time.png"), fullPage: true });

  await page.goto(basePath + `#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row).toContainText("GPT-6.1 Sol Medium (OpenCode)");
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://developers.openai.com/api/docs/models/gpt-6.1-sol");
  await page.screenshot({ path: testInfo.outputPath("opencode-cost.png"), fullPage: true });
});

test("OpenCode has one explicit stock-harness methodology record", async ({ page }, testInfo) => {
  await page.goto(basePath + "#/methodology");
  await expect(page.getByRole("heading", { name: "OpenCode", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "OpenCode", exact: true }) });
  await expect(harness.locator(".harness-models > span")).toHaveCount(1);
  await expect(harness.getByText("GPT-6.1 Sol Medium (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model openai\/gpt-6.1-sol; reasoning effort medium/);
  await expect(page.getByRole("link", { name: /Retained OpenCode harness configuration/ })).toHaveAttribute("href", /batches\/20261017-192226\/method\/validation\/lib\/opencode_harness.rb$/);
  await expect(page.getByText(/Cross-harness comparisons measure the complete agent setup/)).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("opencode-methodology.png"), fullPage: true });
});
