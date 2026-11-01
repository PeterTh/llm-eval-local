import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "beam-1.0-oc-medium";
const batch = "20261025-170121";
const original = "74652eee82e2473660a7e75f3ad5d77fd0e3759c";

test("Beam protocol failure retains the original program and partial accounting", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const id = `matmul_${model}_mpi_r3`;
  await page.goto(`${basePath}#/run/${id}?model-set=all`);
  await expect(page.getByText("Model-caused protocol failure.", { exact: true })).toBeVisible();
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Estimated API cost unavailable", exact: true })).toBeVisible();
  await expect(page.getByText("Usage is incomplete: at least 72,920 tokens", { exact: false })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(`${original}/${batch}/${id}$`));
  await expect(page.getByRole("link", { name: /Termination evidence/ })).toHaveAttribute("href", new RegExp(`batches/${batch}/generation/terminations/${id}\\.json$`));
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByLabel("Token consumption")).not.toContainText("Input tokens (cache included)");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("beam-protocol-failure.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Beam cost and time preserve their different accounting scopes", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/cost?model=${model}`);
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  const costDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const costs = parse(await readFile((await (await costDownload).path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(costs).toHaveLength(1);
  expect(Number(costs[0]!.score_run_count)).toBe(220);
  expect(Number(costs[0]!.cost_run_count)).toBe(219);
  expect(Number(costs[0]!.unavailable_cost_run_count)).toBe(1);
  expect(Number(costs[0]!.estimated_mean_cost_usd)).toBeCloseTo(4.8685698 / 219, 10);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toContainText("Beam 1.0 Medium (OpenCode)");
  await expect(row).toContainText("nebius/fp4");
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://openrouter.ai/reflection/beam-1.0-501b-a23b");
  await page.screenshot({ path: testInfo.outputPath("beam-cost.png"), fullPage: true });

  await page.goto(`${basePath}#/time?model=${model}`);
  await expect(page.locator(".time_points path")).toHaveCount(1);
  const timeDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const times = parse(await readFile((await (await timeDownload).path())!, "utf8"), { columns: true }) as Record<string, string>[];
  expect(times).toHaveLength(1);
  expect(Number(times[0]!.time_run_count)).toBe(220);
  expect(Number(times[0]!.mean_generation_seconds)).toBeCloseTo(15149.097 / 220, 8);
});

test("Beam joins the shared OpenCode methodology record", async ({ page }, testInfo) => {
  await page.goto(`${basePath}#/methodology`);
  await expect(page.getByRole("heading", { name: "OpenCode", exact: true })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "OpenCode", exact: true }) });
  await expect(harness.getByText("Beam 1.0 Medium (OpenCode)", { exact: true })).toHaveAttribute("title", /invoked model opencode-go\/beam-free; reasoning effort medium/);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Claude Code", exact: true })).toHaveCount(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  await page.screenshot({ path: testInfo.outputPath("beam-methodology.png"), fullPage: true });
});
