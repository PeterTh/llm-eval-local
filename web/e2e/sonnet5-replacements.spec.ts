import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const model = "claude-sonnet-5-cc-medium";
const batch = "20260901-162328";
const original = "9ca4eb864529503d811edb1352c8e5b9a6f71c83";
const corrected = "ce15f07db28d3d894f004d50f08352943caa42a8";
const evidence = `batches/${batch}/replacements/20261025-isolated-sonnet5`;

test("Sonnet 5 replacements preserve timing history and remove obsolete failed-program measurements", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  for (const id of [`nbody_${model}_mpi_r3`, `roomsim_${model}_mpi_r5`]) {
    await page.goto(basePath + `#/run/${id}?model-set=all`);
    await expect(page.getByRole("heading", { name: "Validation passed", exact: true })).toBeVisible();
    await expect(page.getByText("Successful benchmark execution.", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /Original generated source directory/ })).toHaveAttribute("href", new RegExp(`${original}/${batch}/${id}$`));
    await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveAttribute("href", new RegExp(`${corrected}/${batch}/${id}$`));
    await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`${evidence}/benchmark/records/`));
  }
  await page.screenshot({ path: testInfo.outputPath("sonnet5-replacement-corrected.png"), fullPage: true });

  await page.goto(basePath + `#/run/black-scholes_${model}_mpi_r2?model-set=all`);
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(original));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveAttribute("href", new RegExp(`${evidence}/benchmark/records/`));

  await page.goto(basePath + `#/run/roomsim_${model}_hybrid_r3?model-set=all`);
  await expect(page.getByText("Validation did not produce a benchmarkable program.", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("href", new RegExp(original));
  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Benchmark JSONL evidence/ })).toHaveCount(0);
  await page.screenshot({ path: testInfo.outputPath("sonnet5-replacement-failed.png"), fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
  expect(errors).toEqual([]);
});
