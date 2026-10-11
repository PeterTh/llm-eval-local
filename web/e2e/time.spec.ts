import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";
import { parse } from "csv-parse/sync";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? "/" + repositoryName + "/" : "/";

test("time efficiency filters, reconciles durations, exports and opens runs", async ({ page }, testInfo) => {
  const problems: string[] = [];
  page.on("pageerror", (error) => problems.push(error.message));
  page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
  await page.goto(basePath + "#/time");
  await expect(page.getByRole("link", { name: "Time Efficiency" })).toHaveClass(/active/);
  const summary = page.getByLabel("Current time efficiency selection summary");
  await expect(summary.getByText("23", { exact: true })).toBeVisible();
  await expect(summary.getByText("5,060", { exact: true })).toHaveCount(2);
  const scale = page.getByRole("combobox", { name: "Time scale" });
  await expect(scale).toHaveValue("linear");
  const points = page.locator(".time_points path");
  const outliers = page.locator(".time_outlier_points path");
  await expect(points).toHaveCount(23);
  await expect(page.locator(".time_boxes path")).toHaveCount(23);
  await expect(page.locator(".time-distribution svg text").filter({ hasText: /^Opus 5 Medium$/ })).toHaveCount(1);
  await expect(outliers.first()).toHaveAttribute("tabindex", "0");
  await page.screenshot({ path: testInfo.outputPath("time-default-linear.png"), fullPage: true });

  // Locate by the generated accessible description, not chart placement.
  const opus = page.locator('.time_points path[aria-label^="Opus 5 Medium;"]');
  await opus.hover({ force: true });
  await expect(page.locator("#vg-tooltip-element")).toContainText("29.62 min");
  await expect(page.locator("#vg-tooltip-element")).toContainText("21.54 min");
  await page.mouse.move(1, 1);

  await scale.selectOption("log");
  await expect(page).toHaveURL(/scale=log/);
  await expect(page.getByText("Mean generation time (min, log scale)", { exact: true })).toBeVisible();
  await expect(page.getByText("Generation time (min, log scale)", { exact: true })).toBeVisible();
  await page.goBack();
  await expect(scale).toHaveValue("linear");
  await page.goForward();
  await expect(scale).toHaveValue("log");

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await page.mouse.click(4, 400);
  await expect(summary.getByText("30", { exact: true })).toBeVisible();
  await expect(summary.getByText("6,600", { exact: true })).toHaveCount(2);
  await expect(points).toHaveCount(30);
  await expect(page.locator(".time_boxes path")).toHaveCount(30);

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("llm-eval-score-time.csv");
  const exported = parse(await readFile((await download.path())!, "utf8"), { columns: true }) as Record<string, string>[];
  const source = parse(await readFile(new URL("../../release/scored_results.csv", import.meta.url), "utf8"), { columns: true }) as Record<string, string>[];
  expect(source).toHaveLength(6600);
  expect(exported).toHaveLength(30);
  for (const row of exported) {
    const selected = source.filter((run) => run.model === row.model);
    const times = selected.map((run) => Number(run.total_time)).sort((a, b) => a - b);
    expect(Number(row.time_run_count)).toBe(220);
    expect(Number(row.mean_generation_seconds)).toBeCloseTo(times.reduce((sum, value) => sum + value, 0) / times.length, 8);
    expect(Number(row.median_generation_seconds)).toBeCloseTo((times[109] + times[110]) / 2, 8);
    expect(Number(row.maximum_generation_seconds)).toBe(times.at(-1));
  }
  expect(Number(exported.find((row) => row.model === "claude-opus-5-cc-medium")!.mean_generation_seconds) / 60).toBeCloseTo(29.62, 2);
  expect(Number(exported.find((row) => row.model === "gpt-5.6-sol-medium")!.mean_generation_seconds) / 60).toBeCloseTo(4.57, 2);

  await page.getByText("Accessible time efficiency table", { exact: true }).click();
  const opusRow = page.locator(".time-data tbody tr").filter({ hasText: "Opus 5 Medium" });
  await expect(opusRow).toContainText("29.62 min");
  await expect(opusRow).toContainText("21.54 min");
  await page.getByText("Accessible time efficiency table", { exact: true }).click();

  // Keep the complete distributions visible, including the longest observation.
  const longest = page.locator('.time_outlier_points path[aria-label*="435.87 min"]');
  await expect(longest).toHaveCount(1);
  const bounds = await longest.evaluate((element) => {
    const point = element.getBoundingClientRect();
    const svg = element.closest("svg")!.getBoundingClientRect();
    return { pointLeft: point.left, pointRight: point.right, svgLeft: svg.left, svgRight: svg.right };
  });
  expect(bounds.pointLeft).toBeGreaterThanOrEqual(bounds.svgLeft);
  expect(bounds.pointRight).toBeLessThanOrEqual(bounds.svgRight);

  await outliers.first().focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/from=time/);
  await expect(page.getByRole("heading", { name: /min generation time/ })).toBeVisible();
  await page.getByRole("link", { name: /Back to Time Efficiency/ }).click();
  await expect(scale).toHaveValue("log");
  await expect(summary.getByText("30", { exact: true })).toBeVisible();

  await points.first().focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/runs\?model=/);
  await page.goBack();
  await page.getByRole("button", { name: /Reset/ }).click();
  await expect(scale).toHaveValue("linear");
  await expect(summary.getByText("23", { exact: true })).toBeVisible();

  await page.goto(basePath + "#/time?model=claude-opus-5-cc-medium&benchmark=black-scholes&backend=omp&scale=log");
  await expect(points).toHaveCount(1);
  await expect(summary.getByText("5", { exact: true })).toHaveCount(2);
  await expect(page.locator(".time_boxes path")).toHaveCount(1);
  const filteredDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const filteredRows = parse(await readFile((await (await filteredDownload).path())!, "utf8"), { columns: true }) as Record<string, string>[];
  const cell = source.filter((run) => run.model === "claude-opus-5-cc-medium" && run.benchmark === "black-scholes" && run.par_type === "omp");
  expect(filteredRows).toHaveLength(1);
  expect(Number(filteredRows[0].mean_generation_seconds)).toBeCloseTo(cell.reduce((sum, run) => sum + Number(run.total_time), 0) / 5, 8);
  await points.first().focus();
  await page.keyboard.press("Space");
  await expect(page).toHaveURL(/benchmark=black-scholes/);
  await expect(page).toHaveURL(/backend=omp/);
  expect(problems).toEqual([]);
});

test("time charts retain labels and complete ranges at every scale and theme", async ({ page }, testInfo) => {
  const problems: string[] = [];
  page.on("pageerror", (error) => problems.push(error.message));
  for (const colorScheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme });
    for (const scale of ["linear", "log"]) {
      await page.goto(basePath + "#/time?model-set=all&scale=" + scale);
      const labels = page.locator(".time_labels text");
      await expect(labels).toHaveCount(30);
      await expect(page.locator(".time_boxes path")).toHaveCount(30);
      const layout = await labels.evaluateAll((elements) => {
        const visible = elements.filter((element) => {
          const style = getComputedStyle(element);
          const box = element.getBoundingClientRect();
          return style.opacity !== "0" && box.width > 0 && box.height > 0;
        });
        const boxes = visible.map((element) => element.getBoundingClientRect());
        let overlaps = 0;
        for (let left = 0; left < boxes.length; left++) {
          for (let right = left + 1; right < boxes.length; right++) {
            if (Math.min(boxes[left].right, boxes[right].right) - Math.max(boxes[left].left, boxes[right].left) > 2
              && Math.min(boxes[left].bottom, boxes[right].bottom) - Math.max(boxes[left].top, boxes[right].top) > 2) overlaps++;
          }
        }
        return { count: visible.length, overlaps, hidden: elements.filter((element) => !visible.includes(element)).map((element) => element.textContent) };
      });
      await page.screenshot({ path: testInfo.outputPath("time-all-" + colorScheme + "-" + scale + ".png"), fullPage: true });
      expect(layout).toEqual({ count: 30, overlaps: 0, hidden: [] });
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width);
    }
  }
  if (testInfo.project.name === "mobile") {
    await page.setViewportSize({ width: 320, height: 844 });
    await page.goto(basePath + "#/time");
    await expect(page.locator(".time_points path")).toHaveCount(23);
    await expect(page.locator(".time_boxes path")).toHaveCount(23);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
    await page.screenshot({ path: testInfo.outputPath("time-320-dark.png"), fullPage: true });
  }
  expect(problems).toEqual([]);
});
