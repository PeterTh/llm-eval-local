import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";
import { allModelCount, defaultModelCount, totalRunCount } from "./release-counts";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const batch = "20261123-155235";

test("default selection keeps the Sol 6.1 comparison group alongside GPT-6.2", async ({ page }, testInfo) => {
  expect([allModelCount, defaultModelCount, totalRunCount]).toEqual([43, 30, 9460]);
  await page.goto(`${basePath}#/tiers`);
  const menu = page.locator(".filter-menu").first();
  await menu.locator("summary").click();
  for (const name of ["GPT-6.1 Sol Medium", "GPT-6.1 Sol XHigh", "GPT-6.1 Sol Medium (OpenCode)", "GPT-6.2 Astra Medium", "GPT-6.2 Sol Medium"]) {
    await expect(menu.getByRole("checkbox", { name, exact: true })).toBeChecked();
  }
  for (const name of ["Fable 5 Medium", "Opus 5 Medium", "Sonnet 5 Medium", "DeepSeek V4 Flash", "GPT-6 Astra Medium", "GPT-6 Sol Medium"]) {
    await expect(menu.getByRole("checkbox", { name, exact: true })).not.toBeChecked();
  }
  await menu.getByRole("button", { name: "All", exact: true }).click();
  await expect(page).toHaveURL(/model-set=all/);
  await expect(page.getByLabel("Current selection summary").getByText("43", { exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(menu).not.toHaveAttribute("open", "");
  await page.screenshot({ path: testInfo.outputPath("gpt62-all-models.png"), fullPage: true });
});

test("GPT-6.2 reviews expose group comparisons and diagnostic evidence", async ({ page }, testInfo) => {
  for (const id of ["black-scholes_gpt-6.2-sol-medium_mpi_r5", "floydwarshall_gpt-6.2-sol-medium_omp_r3", "unstructured_gpt-6.2-astra-medium_hybrid_r2"]) {
    await page.goto(`${basePath}#/run/${id}?model-set=all`);
    for (const name of ["Finding", "Close-group comparison", "Correctness and timing", "Interpretation"]) {
      await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    }
    if (id.startsWith("black-scholes")) {
      await expect(page.getByRole("link", { name: "paired diagnostic", exact: true })).toHaveAttribute("href", /2026-11-25-gpt62-outlier-probes.json$/);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
    await page.screenshot({ path: testInfo.outputPath(`${id}-review.png`), fullPage: true });
  }
});

test("GPT-6.2 corrected sources and the original build failure remain accessible", async ({ page }, testInfo) => {
  const id = "roomsim_gpt-6.2-sol-medium_hybrid_r1";
  await page.goto(`${basePath}#/run/${id}?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`7a0a8b8e28af48d4ee2525c13ced317726536b25/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`1e10bfb901d02f49780de336995fef5b0bf8f5c8/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/benchmark/records`));
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await page.screenshot({ path: testInfo.outputPath("gpt62-corrected-run.png"), fullPage: true });
  await page.goto(`${basePath}#/run/cholesky_gpt-6.2-sol-medium_cuda_r4?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
});

test("GPT-6.2 costs use exact native tokens at Standard rates", async ({ page }, testInfo) => {
  for (const [model, totalCost] of [["gpt-6.2-astra-medium", 142.552352], ["gpt-6.2-sol-medium", 95.6359976]] as const) {
    await page.goto(`${basePath}#/cost?model=${model}`);
    await expect(page.locator(".cost_points path")).toHaveCount(1);
    if (await page.locator(".cost-data").getAttribute("open") === null) {
      await page.getByText("Accessible cost efficiency table", { exact: true }).click();
    }
    const row = page.locator(".cost-data tbody tr");
    await expect(row).toHaveCount(1);
    await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", `https://developers.openai.com/api/docs/models/${model.replace(/-medium$/, "")}`);
    const pending = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export", exact: true }).click();
    const costs = parse(await readFile((await (await pending).path())!, "utf8"), { columns: true }) as Record<string, string>[];
    expect(costs).toHaveLength(1);
    expect(Number(costs[0]!.estimated_mean_cost_usd)).toBeCloseTo(totalCost / 220, 10);
    expect(Number(costs[0]!.recorded_usage_lower_bound_run_count)).toBe(0);
    await page.screenshot({ path: testInfo.outputPath(`${model}-cost.png`), fullPage: true });
  }
});

test("GPT-6.2 shares the Codex methodology record and documents Standard pricing", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/methodology`);
  const heading = page.getByRole("heading", { name: "Codex CLI", exact: true });
  await expect(heading).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: heading });
  for (const family of ["Astra", "Sol"]) {
    await expect(harness.getByText(`GPT-6.2 ${family} Medium`, { exact: true })).toHaveAttribute("title", new RegExp(`invoked model gpt-6.2-${family.toLowerCase()}; reasoning effort medium`));
  }
  await expect(page.getByText(/GPT-6.2 uses Standard pricing, excluding the delayed background tier/)).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("gpt62-methodology.png"), fullPage: true });
});
