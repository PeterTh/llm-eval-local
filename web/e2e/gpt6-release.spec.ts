import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

test("GPT-6 winners expose reviews and exact cost/time evidence", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(basePath + "#/run/qtclustering_gpt-6-astra-medium_mpi_r5?model-set=all");
  await expect(page.getByRole("heading", { name: "Finding", exact: true })).toBeVisible();
  await expect(page.getByText(/^GPT-6 Astra Medium · QT Clustering/)).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", /32f1becd283322d1edff43dd47a3b3bc8e2cdad6/);
  await expect(page.getByLabel("Token consumption")).toContainText("Input tokens (cache included)");
  await expect(page.getByRole("link", { name: /This model in Time Efficiency/ })).toBeVisible();
  expect(errors).toEqual([]);
});

test("failed corrected programs stay invalid and retain both sources and observations", async ({ page }) => {
  for (const id of ["nbody_gpt-6-luna-medium_hybrid_r5", "roomsim_gpt-6-luna-medium_hybrid_r3"]) {
    await page.goto(basePath + `#/run/${id}?model-set=all`);
    await expect(page.getByText(/failed revalidation and was not benchmarked/)).toBeVisible();
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", /3a47d7cba6624f4bdfe004fba3383b5e3c62e93f/);
    await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", /32f1becd283322d1edff43dd47a3b3bc8e2cdad6/);
    await expect(page.getByRole("link", { name: /^Validation JSONL evidence/ })).toHaveAttribute("href", /corrections\/20261001-gpt6-qt\/revalidation/);
    await expect(page.getByRole("link", { name: /Earlier validation JSONL evidence/ })).toHaveAttribute("href", /batches\/20260929-135931\/validation/);
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  }
});

test("twice-corrected historical QT exposes initial, intermediate and final sources", async ({ page }) => {
  await page.goto(basePath + "#/run/qtclustering_claude-sonnet-5-cc-medium_hybrid_r2?model-set=all");
  await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", /db27e2872a28b900024d318f6a3004a3a7fddfa7/);
  await expect(page.getByRole("link", { name: /Intermediate timing-corrected source 1/ })).toHaveAttribute("href", /4500d708ad5c7b5d1594f93704011d6dfbca09a1/);
  await expect(page.getByRole("link", { name: /^Timing-corrected source directory/ })).toHaveAttribute("href", /3a47d7cba6624f4bdfe004fba3383b5e3c62e93f/);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", /corrections\/20261001-gpt6-qt\/benchmark\/records/);
});

test("methodology exposes the exact GPT-6 launch snapshot", async ({ page }) => {
  await page.goto(basePath + "#/methodology");
  await expect(page.getByText("Codex CLI 0.159.0 (GPT-6 campaign)", { exact: true }).first()).toBeVisible();
  const link = page.locator('a[href*="batches/20260929-135931/generation/method/experiment.rb"]');
  await expect(link).toHaveAttribute("href", /\/blob\/[0-9a-f]{40}\//);
  await expect(page.getByText("GPT-6 Astra Medium", { exact: true })).toHaveAttribute("title", /invoked model gpt-6-astra; reasoning effort medium/);
});
