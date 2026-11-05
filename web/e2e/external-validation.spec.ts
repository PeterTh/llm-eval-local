import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

for (const [id, timingFixed, validationCase, evidenceDirectory] of [
  ["unstructured_gpt-5.6-terra-medium_hybrid_r5", false, "unstructured-boundary-v1", "20261101-unstructured-boundary"],
  ["unstructured_gpt-5.6-luna-xhigh_hybrid_r1", true, "unstructured-boundary-v1", "20261101-unstructured-boundary"],
  ["floydwarshall_gpt-5.6-luna-low_hybrid_r3", false, "floyd-integer-hash-v1", "20261103-floyd-integer-hash"],
  ["stencil3d_gpt-5.6-luna-medium_mpi_r2", false, "stencil-interior-v1", "20261103-stencil-interior"],
  ["nbody_claude-opus-4.6_hybrid_r1", true, "nbody-shape-topology-v1", "20261103-shape-topology-full/nbody-shape-topology-v1"],
  ["roomsim_gpt-5.6-sol-xhigh_hybrid_r3", false, "full-array-roomsim-v1", "20261105-full-array-full/eligibility/roomsim"],
  ["nbody_claude-haiku-4.5_hybrid_r3", true, "full-array-nbody-v1", "20261105-full-array-full/eligibility/nbody"],
  ["spmv_gpt-4.1_mpi_r4", false, "full-array-spmv-v1", "20261105-full-array-full/eligibility/spmv"],
] as const) {
  test(`supplemental failure retains historical evidence: ${id}`, async ({ page }, testInfo) => {
    await page.goto(`${basePath}#/run/${id}?model-set=all`);
    await expect(page.getByRole("heading", { name: "Stopped at stage 4", exact: true })).toBeVisible();
    await expect(page.getByText(`Output comparison FAILED (${validationCase})`, { exact: false })).toBeVisible();
    await expect(page.getByRole("link", { name: /Archived benchmark evidence \(excluded\)/ })).toHaveAttribute("href", /benchmark\/records\/.+\.jsonl#L\d+$/);
    await expect(page.getByRole("link", { name: /Earlier validation JSONL evidence/ })).toHaveCount(1);
    await expect(page.getByRole("link", { name: /^Validation JSONL evidence/ })).toHaveAttribute("href", new RegExp(`validation-supplements/${evidenceDirectory}/records\\.jsonl#L\\d+$`));
    await expect(page.getByRole("link", { name: /^Benchmark JSONL evidence/ })).toHaveCount(0);
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(timingFixed ? 1 : 0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
    await page.screenshot({ path: testInfo.outputPath(`${id}.png`), fullPage: true });
  });
}

test("Roomsim retains its excluded historical review and reviewed replacement winner", async ({ page }) => {
  await page.goto(`${basePath}#/run/roomsim_gpt-5.6-sol-xhigh_hybrid_r3?model-set=all`);
  const analysis = page.locator('[aria-labelledby="implementation-analysis-heading"]');
  await expect(analysis).toContainText("failed external validation in the complete-array check");
  await expect(analysis.getByRole("link", { name: "Sol Medium review" })).toHaveAttribute("href", /roomsim_gpt-5\.6-sol-medium_hybrid_r2\.md$/);

  await page.goto(`${basePath}#/run/roomsim_gpt-5.6-sol-medium_hybrid_r2?model-set=all`);
  await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
  await expect(analysis.getByRole("heading", { name: "Finding", exact: true })).toBeVisible();
  await expect(analysis.getByRole("heading", { name: "Close-group comparison", exact: true })).toBeVisible();
  await expect(analysis).toContainText("All 320 observed distances pass");
  const numericLineCounts = await analysis.locator("td").evaluateAll(cells => cells
    .filter(cell => /^\d+$/.test(cell.textContent ?? ""))
    .map(cell => {
      const range = document.createRange();
      range.selectNodeContents(cell);
      return range.getClientRects().length;
    }));
  expect(numericLineCounts).toEqual(Array(12).fill(1));
});
