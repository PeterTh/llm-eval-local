import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const campaigns = [
  {
    name: "Sol 6.1", model: "gpt-6.1-sol-oc-medium", nativeModel: "gpt-6.1-sol-medium",
    label: "GPT-6.1 Sol Medium (OpenCode)", batch: "20261017-192226", totalSeconds: 75839.228,
    originalCommit: "352c09d57e14ef93744aa8cc741ff52884079e5f",
    correctedCommit: "9012afd8480bb000ff7b01581a91c6b680ef2394",
    correctedRun: "roomsim_gpt-6.1-sol-oc-medium_hybrid_r1", failedRun: "matmul_gpt-6.1-sol-oc-medium_mpi_r2",
    pricingSource: "https://developers.openai.com/api/docs/models/gpt-6.1-sol",
  },
  {
    name: "Luna 6", model: "gpt-6-luna-oc-medium", nativeModel: "gpt-6-luna-medium",
    label: "GPT-6 Luna Medium (OpenCode)", batch: "20261018-224015", totalSeconds: 15462.03,
    originalCommit: "fd64978a13b9a4f3ac6a5e368972316d0c159aa1",
    correctedCommit: "fdf3ef5283428bb38fcfd6ec116e9fa03defe229",
    correctedRun: "black-scholes_gpt-6-luna-oc-medium_mpi_r1", failedRun: "qtclustering_gpt-6-luna-oc-medium_cuda_r1",
    pricingSource: "https://developers.openai.com/api/docs/models/gpt-6-luna",
  },
  {
    name: "Haiku 5.5", model: "claude-haiku-5.5-oc-medium", nativeModel: "claude-haiku-5.5-cc-medium",
    label: "Haiku 5.5 Medium (OpenCode)", batch: "20261025-170040", totalSeconds: 207393.963,
    originalCommit: "24648e59045c3e8d7280119627a7bccde1da4f2f",
    correctedCommit: "beb7571b6687c47a3989b0632f1e7e164e848f65",
    correctedRun: "black-scholes_claude-haiku-5.5-oc-medium_mpi_r2", failedRun: "roomsim_claude-haiku-5.5-oc-medium_omp_r2",
    pricingSource: "https://platform.claude.com/docs/en/models/haiku-5-5/overview",
  },
];

for (const campaign of campaigns) {
  const { name, model, nativeModel, originalCommit, correctedCommit, batch } = campaign;

  test(`${name} OpenCode corrected run retains both source revisions and exact token metadata`, async ({ page }, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(basePath + `#/run/${campaign.correctedRun}?model-set=all`);
    await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
    await expect(page.getByText("Successful benchmark execution.", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit + "/" + batch + "/"));
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(correctedCommit + "/" + batch + "/"));
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp("batches/" + batch + "/benchmark/records"));
    await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
    await expect(page.getByText("Recovered generation duration.", { exact: true })).toHaveCount(0);
    await page.screenshot({ path: testInfo.outputPath("opencode-corrected-run.png"), fullPage: true });
    expect(errors).toEqual([]);
  });

  test(`${name} OpenCode ordinary validation failure is retained without benchmarking`, async ({ page }) => {
    await page.goto(basePath + `#/run/${campaign.failedRun}?model-set=all`);
    await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(originalCommit));
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
  });

  test(`${name} OpenCode time and cost remain separate from the native profile`, async ({ page }, testInfo) => {
    await page.goto(basePath + `#/time?model=${model}&model=${nativeModel}`);
    await expect(page.locator(".time_points path")).toHaveCount(2);
    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "Export", exact: true }).click();
    const download = await downloadPromise;
    const rows = parse(await readFile((await download.path())!, "utf8"), { columns: true }) as Record<string, string>[];
    expect(rows).toHaveLength(2);
    const opencode = rows.find((row) => row.model === model)!;
    expect(Number(opencode.time_run_count)).toBe(220);
    expect(Number(opencode.recovered_time_run_count)).toBe(0);
    expect(Number(opencode.mean_generation_seconds)).toBeCloseTo(campaign.totalSeconds / 220, 8);
    await page.screenshot({ path: testInfo.outputPath("opencode-native-time.png"), fullPage: true });

    await page.goto(basePath + `#/cost?model=${model}`);
    await expect(page.locator(".cost_points path")).toHaveCount(1);
    await page.getByText("Accessible cost efficiency table", { exact: true }).click();
    const row = page.locator(".cost-data tbody tr");
    await expect(row).toHaveCount(1);
    await expect(row).toContainText(campaign.label);
    await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", campaign.pricingSource);
    await page.screenshot({ path: testInfo.outputPath("opencode-cost.png"), fullPage: true });
  });
}

test("OpenCode has one explicit stock-harness methodology record", async ({ page }, testInfo) => {
  await page.goto(basePath + "#/methodology");
  await expect(page.getByRole("heading", { name: "OpenCode", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "OpenCode", exact: true }) });
  await expect(harness.locator(".harness-models > span")).toHaveCount(4);
  await expect(harness.getByText("GPT-6.1 Sol Medium (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model openai\/gpt-6.1-sol; reasoning effort medium/);
  await expect(harness.getByText("GPT-6 Luna Medium (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model openai\/gpt-6-luna; reasoning effort medium/);
  await expect(harness.getByText("DeepSeek V4.1 Flash High (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model opencode-go\/deepseek-v4.1-flash; reasoning effort high/);
  await expect(harness.getByText("Haiku 5.5 Medium (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model opencode-go\/claude-haiku-5-5; reasoning effort medium/);
  await expect(page.getByRole("link", { name: /Retained OpenCode harness configuration/ })).toHaveAttribute("href", /batches\/20261025-170040\/method\/validation\/lib\/opencode_harness.rb$/);
  await expect(page.getByRole("link", { name: /Luna 6 harness comparison/ })).toHaveAttribute("href", /analysis\/notes\/2026-10-19-luna6-harness-comparison.md$/);
  await expect(page.getByRole("link", { name: /Haiku 5.5 harness comparison/ })).toHaveAttribute("href", /analysis\/notes\/2026-10-28-haiku55-harness-comparison.md$/);
  await expect(page.getByText(/Cross-harness comparisons measure the complete agent and provider setup/)).toBeVisible();
  await expect(page.getByText(/Haiku uses the Anthropic adapter's adaptive thinking at medium effort through OpenCode Go/)).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("opencode-methodology.png"), fullPage: true });
});

test("Haiku OpenCode request-tier cost uses native per-request output", async ({ page }) => {
  await page.goto(basePath + "#/cost?model=claude-haiku-5.5-oc-medium");
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row.getByRole("cell", { name: "$0.1246", exact: true })).toBeVisible();
  await expect(row).not.toContainText("Mixed-tier output splits derived");
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const download = await downloadPromise;
  const rows = parse(await readFile((await download.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(rows).toHaveLength(1);
  expect(Number(rows[0]!.estimated_mean_cost_usd)).toBeCloseTo(27.421071570 / 220, 9);
  await page.goto(basePath + "#/methodology");
  await expect(page.getByText(/OpenCode records output per request directly/)).toBeVisible();
});
