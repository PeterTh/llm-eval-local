import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

test("Opus 5.5 winner retains original and corrected sources plus its review", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(basePath + "#/run/cholesky_claude-opus-5.5-cc-medium_hybrid_r1?model-set=all");
  await expect(page.getByRole("heading", { name: "Finding", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Close-group comparison", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", /d2d8446a37657d114b3ea1c171767218539cae54\/20261002-142720/);
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", /a14535a1a0101b4ddbc725d374772c2da529c824\/20261002-142720/);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", /batches\/20261002-142720\/benchmark\/records/);
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await page.screenshot({ path: testInfo.outputPath("opus55-corrected-winner.png"), fullPage: true });
  expect(errors).toEqual([]);
});

test("Opus 5.5 outlier review includes retained phase comparison", async ({ page }, testInfo) => {
  await page.goto(basePath + "#/run/roomsim_claude-opus-5.5-cc-medium_cuda_r3");
  await expect(page.getByRole("heading", { name: "Finding", exact: true })).toBeVisible();
  await expect(page.getByRole("cell", { name: "1,668 ms", exact: true })).toBeVisible();
  const tableWidths = await page.locator(".implementation-analysis-table").evaluate((element) => ({
    client: element.clientWidth, content: element.scrollWidth,
  }));
  expect(tableWidths.content).toBeLessThanOrEqual(tableWidths.client + 1);
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", /d2d8446a37657d114b3ea1c171767218539cae54/);
  await page.screenshot({ path: testInfo.outputPath("opus55-outlier-review.png"), fullPage: true });
});

test("Opus 5.5 pricing and pinned Claude Code harness are available", async ({ page }, testInfo) => {
  await page.goto(basePath + "#/cost?model=claude-opus-5.5-cc-medium");
  await expect(page.locator(".cost_points path")).toHaveCount(1);
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const row = page.locator(".cost-data tbody tr");
  await expect(row).toContainText("Opus 5.5 Medium");
  await expect(row.getByRole("link", { name: "Pricing source" })).toHaveAttribute("href", "https://platform.claude.com/docs/en/about-claude/pricing");
  await page.goto(basePath + "#/methodology");
  const harness = page.locator(".harness-record").filter({ has: page.getByRole("heading", { name: "Claude Code 2.1.287", exact: true }) });
  await expect(harness.getByText("Opus 5.5 Medium", { exact: true })).toHaveAttribute("title", /invoked model claude-opus-5-5; reasoning effort medium/);
  await harness.getByText("Exact harness parameters", { exact: true }).click();
  await expect(harness.locator(".harness-parameters code")).toContainText("WebSearch,WebFetch,Agent,Task");
  await page.screenshot({ path: testInfo.outputPath("opus55-methodology.png"), fullPage: true });
});
