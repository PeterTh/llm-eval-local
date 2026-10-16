import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

test("Haiku timing correction retains both sources and benchmark evidence", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(basePath + "#/run/qtclustering_claude-haiku-5.5-cc-medium_mpi_r1?model-set=all");
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(page.getByText("Successful benchmark execution.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", /71ba7cc523997c8fd1537d7a8159b583f260793d\/20261012-111947/);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", /778f868b8e30433e60115c46bf01dbf84c609765\/20261012-111947/);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", /batches\/20261012-111947\/benchmark\/records/);
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await page.screenshot({ path: testInfo.outputPath("haiku55-corrected-run.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Haiku native validation failure stays unbenchmarked", async ({ page }) => {
  await page.goto(basePath + "#/run/nbody_claude-haiku-5.5-cc-medium_hybrid_r2?model-set=all");
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", /71ba7cc523997c8fd1537d7a8159b583f260793d/);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
});

test("Haiku context pricing and shared Claude harness are visible", async ({ page }, testInfo) => {
  await page.goto(basePath + "#/cost?model=claude-haiku-5.5-cc-medium");
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toHaveCount(1);
  await expect(row).toContainText("Haiku 5.5 Medium");
  await expect(row.getByRole("cell", { name: "$0.0908", exact: true })).toBeVisible();
  await expect(row).toContainText("Mixed-tier output splits derived");
  await expect(row.getByRole("link", { name: "Pricing source", exact: true })).toHaveAttribute("href", "https://platform.claude.com/docs/en/models/haiku-5-5/overview");
  await page.screenshot({ path: testInfo.outputPath("haiku55-cost.png"), fullPage: true });
  await page.goto(basePath + "#/methodology");
  await expect(page.getByRole("heading", { name: /^Claude Code/ })).toHaveCount(1);
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Claude Code", exact: true }) });
  await expect(harness.locator(".harness-models > span")).toHaveCount(6);
  await expect(harness.getByText("Haiku 5.5 Medium", { exact: true })).toHaveAttribute("title", /invoked model claude-haiku-5-5; reasoning effort medium/);
  await expect(page.getByText(/Haiku 5.5 uses request-length-dependent rates/)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("haiku55-methodology.png"), fullPage: true });
});
