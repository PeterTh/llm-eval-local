import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "deepseek-v4.1-flash-oc-high";
const batch = "20261019-134042";
const original = "40ad0bc6da259d4584e75b8f23f43c77e9751b24";
const corrected = "65363cf3710daa9e0d3409306efee5a49e18c8dd";

test("DeepSeek retains corrected source history and ordinary validation failures", async ({ page }, testInfo) => {
  await page.goto(basePath + `#/run/black-scholes_${model}_mpi_r2?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`${original}/${batch}/`));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`${corrected}/${batch}/`));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/benchmark/records`));
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await expect(page.getByText("Model-caused termination.", { exact: true })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("deepseek-corrected-run.png"), fullPage: true });

  await page.goto(basePath + `#/run/cholesky_${model}_hybrid_r3?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(original));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
});

test("DeepSeek model terminations retain scientific results without a full-task cost", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  for (const [suffix, lowerBound] of [["mpi_r2", "351,385"], ["hybrid_r4", "1,224,117"], ["hybrid_r5", "2,330,386"]]) {
    const id = `qtclustering_${model}_${suffix}`;
    await page.goto(basePath + `#/run/${id}?model-set=all`);
    await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
    await expect(page.getByText("Model-caused termination.", { exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Estimated API cost unavailable", exact: true })).toBeVisible();
    await expect(page.getByText(`Usage is incomplete: at least ${lowerBound} tokens`, { exact: false })).toBeVisible();
    await expect(page.getByRole("link", { name: /Termination evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/generation/terminations/${id}\\.json$`));
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(1);
    await expect(page.getByLabel("Token consumption")).not.toContainText("Input tokens (cache included)");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
    await page.screenshot({ path: testInfo.outputPath(`deepseek-terminated-${suffix}.png`), fullPage: true });
  }
  expect(errors).toEqual([]);
});

test("DeepSeek cost and time exports keep their distinct observation counts", async ({ page }, testInfo) => {
  await page.goto(basePath + `#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await expect(page.getByText("3 scored runs have no cost estimate.", { exact: true })).toBeVisible();
  const costDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const costRows = parse(await readFile((await (await costDownload).path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(costRows).toHaveLength(1);
  expect(Number(costRows[0]!.score_run_count)).toBe(220);
  expect(Number(costRows[0]!.cost_run_count)).toBe(217);
  expect(Number(costRows[0]!.unavailable_cost_run_count)).toBe(3);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  await expect(page.locator(".cost-data tbody tr")).toContainText("DeepSeek V4.1 Flash High (OpenCode)");
  await expect(page.locator(".cost-data tbody tr")).toContainText("baidu/fp8");
  await page.screenshot({ path: testInfo.outputPath("deepseek-partial-cost.png"), fullPage: true });

  await page.goto(basePath + `#/time?model=${model}`);
  await expect(page.locator(".time_points path")).toHaveCount(1);
  const timeDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const timeRows = parse(await readFile((await (await timeDownload).path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(timeRows).toHaveLength(1);
  expect(Number(timeRows[0]!.time_run_count)).toBe(220);
  expect(Number(timeRows[0]!.mean_generation_seconds)).toBeCloseTo(274940.692 / 220, 8);
});

test("DeepSeek scoped replacements use only current source and measurement evidence", async ({ page }, testInfo) => {
  const replacementOriginal = "2c84ee55733daf9fc48a869e5d1f4a068f404f1f";
  const replacementCorrected = "ce4a44804c3a5dca64f03c4ec524df959238940f";
  const evidence = `batches/${batch}/replacements/20261024-isolated`;
  await page.goto(basePath + `#/run/roomsim_${model}_hybrid_r1?model-set=all`);
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(replacementOriginal));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(replacementCorrected));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`${evidence}/benchmark/records`));
  await expect(page.getByText(/contaminat/i)).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("deepseek-replacement-corrected.png"), fullPage: true });

  await page.goto(basePath + `#/run/roomsim_${model}_hybrid_r4?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(replacementOriginal));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByText(/contaminat/i)).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("deepseek-replacement-failed.png"), fullPage: true });
});
