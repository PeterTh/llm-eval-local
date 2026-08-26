import { expect, test, type Page } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

function watchPage(page: Page): string[] {
  const problems: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") problems.push(`console: ${message.text()}`);
  });
  page.on("requestfailed", (request) => problems.push(`network: ${request.url()} ${request.failure()?.errorText ?? "failed"}`));
  page.on("response", (response) => {
    if (response.status() >= 400) problems.push(`http ${response.status()}: ${response.url()}`);
  });
  return problems;
}

async function goto(page: Page, route: string): Promise<void> {
  await page.goto(`${basePath}#${route}`);
}

test("tier overview filters, exports, and drills into its source runs", async ({ page }, testInfo) => {
  const problems = watchPage(page);
  await goto(page, "/tiers");
  const tieredSuccessLink = page.getByRole("link", { name: "Tiered Success" });
  await expect(tieredSuccessLink).toHaveClass(/active/);
  const activeUnderline = await tieredSuccessLink.evaluate((link) => {
    const linkStyle = getComputedStyle(link);
    const underlineStyle = getComputedStyle(link, "::after");
    return {
      paddingLeft: linkStyle.paddingLeft,
      paddingRight: linkStyle.paddingRight,
      underlineLeft: underlineStyle.left,
      underlineRight: underlineStyle.right,
    };
  });
  expect(activeUnderline).toEqual({
    paddingLeft: "0px",
    paddingRight: activeUnderline.paddingRight,
    underlineLeft: "0px",
    underlineRight: activeUnderline.paddingRight,
  });

  const selectionSummary = page.getByLabel("Current selection summary");
  const modelMenu = page.locator(".filter-menu").first();
  await expect(modelMenu.locator("summary strong")).toHaveText("Default");
  await expect(selectionSummary.getByText("14", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("6.45", { exact: true })).toBeVisible();

  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();

  await modelMenu.locator("summary").click();
  await expect(modelMenu.getByRole("button", { name: "Default", pressed: true })).toBeVisible();
  await expect(modelMenu.getByRole("button", { name: "All", exact: true })).toBeVisible();
  await expect(modelMenu.getByRole("button", { name: "Select all" })).toBeVisible();
  for (const model of [
    "Qwen 3.6 27B U-DQ4 Pi-T",
    "GPT-5.6 Luna Low", "GPT-5.6 Luna XHigh",
    "GPT-5.6 Terra Low", "GPT-5.6 Terra XHigh",
    "GPT-5.6 Sol Low", "GPT-5.6 Sol XHigh",
  ]) {
    await expect(modelMenu.getByRole("checkbox", { name: model })).not.toBeChecked();
  }
  for (const model of ["GPT-5.6 Luna Medium", "GPT-5.6 Terra Medium", "GPT-5.6 Sol Medium"]) {
    await expect(modelMenu.getByRole("checkbox", { name: model })).toBeChecked();
  }

  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await expect(page).toHaveURL(/model-set=all/);
  await expect(modelMenu.locator("summary strong")).toHaveText("All models");
  await expect(selectionSummary.getByText("21", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText(/4[,.]620/, { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("6.61", { exact: true })).toBeVisible();
  await expect(page.locator(".chart svg.marks")).toBeVisible();
  await expect(page.locator(".mark-rect path").first()).toBeVisible();

  const tierLabelLayout = await page.evaluate(() => {
    const datumKey = (element: Element): string | null => {
      const sceneItem = (element as Element & { __data__?: { datum?: Record<string, unknown> } }).__data__;
      const datum = sceneItem?.datum;
      return typeof datum?.modelId === "string" && typeof datum.bandId === "string"
        ? `${datum.modelId}:${datum.bandId}`
        : null;
    };
    const segmentWidths = new Map<string, number>();
    document.querySelectorAll(".analysis-panel .mark-rect path").forEach((segment) => {
      const key = datumKey(segment);
      if (key) segmentWidths.set(key, segment.getBoundingClientRect().width);
    });
    return [...document.querySelectorAll(".analysis-panel svg .role-mark.mark-text text")].flatMap((label) => {
      const key = datumKey(label);
      return key ? [{ key, segmentWidth: segmentWidths.get(key) ?? 0 }] : [];
    });
  });
  expect(tierLabelLayout.length).toBeGreaterThan(0);
  expect(Math.min(...tierLabelLayout.map(({ segmentWidth }) => segmentWidth))).toBeGreaterThanOrEqual(
    testInfo.project.name === "mobile" ? 23 : 27,
  );
  const visibleTierLabels = tierLabelLayout.map(({ key }) => key);
  if (testInfo.project.name === "desktop") {
    expect(visibleTierLabels).toEqual(expect.arrayContaining([
      "gpt-4.1:good-top",
      "gemini-3-pro-preview:no-speedup",
      "qwen3.7-plus:no-speedup",
      "gpt-5.6-terra-low:invalid",
    ]));
    expect(visibleTierLabels).not.toContain("qwen-3.6-27B-udq4-pi-t:no-speedup");
  }

  await modelMenu.getByRole("button", { name: "Select all" }).click();
  await expect(modelMenu.locator("summary strong")).toHaveText("21 models");
  expect(await page.evaluate(() => new URLSearchParams(location.hash.split("?")[1] ?? "").getAll("model"))).toHaveLength(21);
  await modelMenu.getByRole("button", { name: "Default" }).click();
  await expect(page).toHaveURL(/#\/tiers$/);
  await expect(modelMenu.locator("summary strong")).toHaveText("Default");
  await expect(selectionSummary.getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await expect(modelMenu.locator("summary strong")).toHaveText("All models");

  const aboutMenu = page.locator(".about-menu");
  const aboutSummary = aboutMenu.locator("summary");
  await aboutSummary.click();
  await expect(aboutMenu).toHaveAttribute("open", "");
  await expect(aboutMenu.getByRole("link", { name: "Citation information" })).toHaveAttribute("href", "#/cite?model-set=all");
  await expect(aboutMenu.getByText("Dataset snapshot")).toHaveCount(0);
  await expect(aboutMenu.getByText(/current publication target/)).toHaveCount(0);
  await expect(aboutMenu.getByText(/lists the authors and copyable BibTeX/)).toBeVisible();
  await page.getByRole("link", { name: "LLM Autoparallelization Benchmark home" }).click();
  await expect(aboutMenu).not.toHaveAttribute("open", "");
  await aboutSummary.click();
  await page.keyboard.press("Escape");
  await expect(aboutMenu).not.toHaveAttribute("open", "");
  await expect(aboutSummary).toBeFocused();

  await modelMenu.locator("summary").click();
  await page.getByRole("checkbox", { name: "Haiku 4.5" }).click();
  await expect(page).toHaveURL(/model=claude-haiku-4.5/);
  await expect(modelMenu.locator("summary strong")).toHaveText("Haiku 4.5");
  await expect(page.getByLabel("Current selection summary").getByText("220", { exact: true })).toBeVisible();
  await page.locator(".brand-name").click();
  await expect(modelMenu).not.toHaveAttribute("open", "");

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: /Export records/ }).click();
  expect((await downloadPromise).suggestedFilename()).toBe("llm-eval-tiered-selection.csv");

  const chartExport = page.getByLabel("Export chart");
  await expect(chartExport).toBeVisible();
  const actionLayout = await chartExport.evaluate((summary) => {
    const chart = summary.closest(".chart")!;
    const summaryRect = summary.getBoundingClientRect();
    const chartRect = chart.getBoundingClientRect();
    return {
      topInset: summaryRect.top - chartRect.top,
      rightInset: chartRect.right - summaryRect.right,
      zIndex: getComputedStyle(summary).zIndex,
      iconMask: getComputedStyle(summary, "::before").maskImage,
      embeddedIconDisplay: getComputedStyle(summary.querySelector("svg")!).display,
    };
  });
  expect(actionLayout.topInset).toBeGreaterThanOrEqual(10);
  expect(actionLayout.rightInset).toBeGreaterThanOrEqual(10);
  expect(actionLayout.zIndex).toBe("2");
  expect(actionLayout.iconMask).not.toBe("none");
  expect(actionLayout.embeddedIconDisplay).toBe("none");
  await chartExport.click();
  await expect(page.getByText("Save as SVG")).toBeVisible();
  await expect(page.getByText("Save as PNG")).toBeVisible();
  await expect(page.locator(".vega-actions")).toHaveCSS("z-index", "3");
  await chartExport.click();

  await page.locator(".mark-rect path").first().click({ force: true });
  await expect(page).toHaveURL(/#\/runs\?model=claude-haiku-4.5&band=/);
  await expect(page.getByRole("heading", { name: /matching runs/ })).toBeVisible();
  await page.goBack();
  await expect(page.getByRole("link", { name: "Tiered Success" })).toHaveClass(/active/);
  await page.goForward();
  await expect(page.getByRole("heading", { name: /matching runs/ })).toBeVisible();
  expect(problems).toEqual([]);
});

test("model scores filters distributions and opens individual runs", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/scores");
  const scoresLink = page.getByRole("link", { name: "Model Scores" });
  await expect(scoresLink).toHaveClass(/active/);
  await expect(page.getByRole("heading", { name: "Model Scores" })).toBeVisible();
  await expect(page.getByLabel("Current score selection summary").getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await expect(page.locator(".score-analysis .chart svg.marks")).toBeVisible();
  await expect(page.locator(".score-analysis .mark-rect path").first()).toBeVisible();
  const scoreRowBands = page.locator(".score-analysis .score_row_bands_marks path");
  await expect(scoreRowBands).toHaveCount(7);

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("checkbox", { name: "Haiku 4.5" }).click();
  await expect(page).toHaveURL(/model=claude-haiku-4.5/);
  await expect(page.getByLabel("Current score selection summary").getByText("220", { exact: true })).toBeVisible();
  await expect(scoreRowBands).toHaveCount(0);
  await page.getByRole("combobox", { name: "Order" }).selectOption("strongest");
  await expect(page).toHaveURL(/sort=strongest/);

  const box = page.locator('.score-analysis [aria-roledescription="box"]').first();
  const scorePoints = page.locator('.score-analysis svg [role="button"][aria-label^="Run "]');
  await expect(box).toBeVisible();
  await expect(scorePoints.first()).toBeVisible();
  const boxBounds = await box.boundingBox();
  const pointCenters = await scorePoints.evaluateAll((marks) => marks.map((mark) => {
    const bounds = mark.getBoundingClientRect();
    return bounds.top + bounds.height / 2;
  }));
  expect(boxBounds).not.toBeNull();
  const boxCenter = boxBounds!.y + boxBounds!.height / 2;
  expect(Math.max(...pointCenters.map((center) => Math.abs(center - boxCenter)))).toBeLessThanOrEqual(11);

  const meanMarker = page.locator('.score-analysis [aria-label^="meanScore"]').first();
  await meanMarker.hover({ force: true });
  const summaryTooltip = page.locator("#vg-tooltip-element");
  await expect(summaryTooltip).toContainText("Lower whisker");
  await expect(summaryTooltip).toContainText("Median");
  await expect(summaryTooltip).toContainText("Upper whisker");
  await expect(summaryTooltip).toContainText("Outliers");
  await page.mouse.move(1, 1);
  await expect(summaryTooltip).toBeHidden();

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: /Export records/ }).click();
  expect((await downloadPromise).suggestedFilename()).toBe("llm-eval-model-scores.csv");

  // The final SVG point is painted on top when runs share a score and nearly share jitter.
  const scorePoint = scorePoints.last();
  await expect(scorePoint).toBeVisible();
  await expect(scorePoint).toHaveAttribute("tabindex", "0");
  await scorePoint.hover({ force: true });
  const tooltip = page.locator("#vg-tooltip-element");
  await expect(tooltip).toBeVisible();
  await expect(tooltip).toContainText("Run");
  await expect(tooltip).toContainText("Benchmark");
  await expect(tooltip).toContainText("Repetition");
  await expect(tooltip).toContainText("Tukey outlier");

  await scorePoint.focus();
  await expect(scorePoint).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/run\/.*model=claude-haiku-4.5.*sort=strongest.*from=scores/);
  await expect(page.getByRole("heading", { name: /claude-haiku-4.5/ })).toBeVisible();
  const back = page.getByRole("link", { name: /Back to Model Scores/ });
  await expect(back).toHaveAttribute("href", /#\/scores\?model=claude-haiku-4.5&sort=strongest/);
  await back.click();
  await expect(page.getByRole("link", { name: "Model Scores", exact: true })).toHaveClass(/active/);
  await expect(page.getByLabel("Current score selection summary").getByText("220", { exact: true })).toBeVisible();
  expect(problems).toEqual([]);
});

test("performance compares successful timings with a fixed full-cell baseline", async ({ page }, testInfo) => {
  const problems = watchPage(page);
  await goto(page, "/performance");
  const performanceLink = page.getByRole("link", { name: "Performance", exact: true });
  await expect(performanceLink).toHaveClass(/active/);
  await expect(page.getByRole("heading", { name: "Performance" })).toBeAttached();
  await expect(page.getByRole("heading", { name: "Floyd–Warshall · OpenMP" })).toBeVisible();

  const selectionSummary = page.getByLabel("Current performance selection summary");
  await expect(selectionSummary.getByText("14", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("59", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("11", { exact: true })).toBeVisible();
  await expect(page.getByRole("combobox", { name: "Benchmark" })).toHaveValue("floydwarshall");
  await expect(page.getByRole("combobox", { name: "Target" })).toHaveValue("omp");
  await expect(page.getByRole("combobox", { name: "Order" })).toHaveValue("fastest");
  await expect(page.getByRole("combobox", { name: "Values" })).toHaveValue("absolute");
  await expect(page.getByRole("combobox", { name: "Scale" })).toHaveValue("log");
  await expect(page.getByRole("checkbox", { name: "Show measurement ranges" })).not.toBeChecked();

  const chart = page.locator(".performance-analysis .chart");
  await expect(chart.locator("svg.marks")).toBeVisible();
  const runPoints = chart.locator('svg [role="button"][aria-label^="Run "]');
  await expect(runPoints).toHaveCount(59);
  await expect(page.locator(".performance-analysis + .accessible-data tbody tr").first().locator("th")).toHaveText("GPT-5.6 Sol Medium");

  const pointRows = await runPoints.evaluateAll((marks) => {
    const rows = new Map<string, { centers: number[]; shapePaths: Set<string> }>();
    for (const mark of marks) {
      const label = mark.getAttribute("aria-label") ?? "";
      const model = label.split("; ")[1];
      const bounds = mark.getBoundingClientRect();
      if (!model || bounds.height === 0) continue;
      const row = rows.get(model) ?? { centers: [], shapePaths: new Set<string>() };
      row.centers.push(bounds.top + bounds.height / 2);
      row.shapePaths.add(mark.getAttribute("d") ?? "");
      rows.set(model, row);
    }
    return [...rows].map(([model, row]) => ({
      model,
      centers: row.centers,
      shapePaths: [...row.shapePaths],
    }));
  });
  const fivePointRow = pointRows.find((row) => row.centers.length === 5);
  expect(fivePointRow, "expected at least one model with five successful runs").toBeDefined();
  const pointSpread = Math.max(...fivePointRow!.centers) - Math.min(...fivePointRow!.centers);
  expect(pointSpread).toBeGreaterThan(testInfo.project.name === "mobile" ? 28 : 34);
  expect(pointRows.every((row) => row.shapePaths.length === 1)).toBe(true);
  const rowsByPosition = [...pointRows].sort((left, right) =>
    Math.min(...left.centers) - Math.min(...right.centers));
  expect(new Set(rowsByPosition.map((row) => row.shapePaths[0])).size).toBe(4);
  for (let index = 1; index < rowsByPosition.length; index += 1) {
    expect(rowsByPosition[index]!.shapePaths[0]).not.toBe(rowsByPosition[index - 1]!.shapePaths[0]);
  }
  const pointSizes = await runPoints.evaluateAll((marks) => {
    const sizes = new Map<string, number>();
    for (const mark of marks) {
      const sceneItem = (mark as SVGElement & { __data__?: { datum?: Record<string, unknown> } }).__data__;
      const shape = sceneItem?.datum?.pointShape;
      const size = sceneItem?.datum?.pointSize;
      if (typeof shape === "string" && typeof size === "number") sizes.set(shape, size);
    }
    return Object.fromEntries(sizes);
  });
  expect(pointSizes["triangle-up"]).toBeGreaterThan(pointSizes.circle!);
  expect(pointSizes.diamond).toBeGreaterThan(pointSizes.square!);

  const rowBands = chart.locator(".performance_row_bands_marks path");
  await expect(rowBands).toHaveCount(7);
  const medianRules = chart.locator(".performance_model_medians_marks path");
  await expect(medianRules).toHaveCount(14);
  const medianBounds = await medianRules.first().boundingBox();
  expect(medianBounds).not.toBeNull();
  expect(medianBounds!.height).toBeGreaterThan(pointSpread + 4);

  await runPoints.first().hover({ force: true });
  const tooltip = page.locator("#vg-tooltip-element");
  await expect(tooltip).toBeVisible();
  await expect(tooltip).toContainText("Median");
  await expect(tooltip).toContainText("Measurements");
  await expect(tooltip).toContainText("Relative to fastest");
  await expect(tooltip).toContainText("Source evidence");
  await expect(tooltip).not.toContainText("Score");
  await page.mouse.move(1, 1);

  const modelLabel = chart.locator(".mark-text.role-mark text").filter({ hasText: /^GPT-5\.6 Sol Medium$/ });
  await modelLabel.hover({ force: true });
  await expect(tooltip).toContainText("Agent harness");
  await expect(tooltip).toContainText("Codex CLI");
  await expect(tooltip).toContainText("Invocation");
  await page.mouse.move(1, 1);

  const rangeRules = chart.locator(".mark-rule.role-mark line, .mark-rule.role-mark path");
  await expect(rangeRules).toHaveCount(0);
  await page.getByRole("checkbox", { name: "Show measurement ranges" }).click();
  await expect(page.getByRole("checkbox", { name: "Show measurement ranges" })).toBeChecked();
  await expect(page).toHaveURL(/ranges=shown/);
  await expect(rangeRules).toHaveCount(59);
  await page.getByRole("combobox", { name: "Values" }).selectOption("relative");
  await page.getByRole("combobox", { name: "Scale" }).selectOption("linear");
  await page.getByRole("combobox", { name: "Order" }).selectOption("slowest");
  await expect(page).toHaveURL(/mode=relative/);
  await expect(page).toHaveURL(/scale=linear/);
  await expect(page).toHaveURL(/order=slowest/);
  await expect(page.getByText(/Relative values use the full-cell fastest median of 1[,.]274 ms/)).toBeVisible();

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("checkbox", { name: "Haiku 4.5" }).click();
  await expect(page).toHaveURL(/model=claude-haiku-4.5/);
  await expect(selectionSummary.getByText("1", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("2", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("3", { exact: true })).toBeVisible();
  await expect(page.getByText(/full-cell fastest median of 1[,.]274 ms/)).toBeVisible();

  const filteredPoint = chart.locator('svg [role="button"][aria-label^="Run "]').first();
  await filteredPoint.focus();
  await expect(filteredPoint).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/run\//);
  for (const parameter of [
    "model=claude-haiku-4.5", "mode=relative", "scale=linear", "ranges=shown", "order=slowest", "from=performance",
  ]) {
    await expect(page).toHaveURL(new RegExp(parameter));
  }
  const back = page.getByRole("link", { name: /Back to performance/ });
  const backHref = await back.getAttribute("href");
  expect(backHref).toContain("#/performance?");
  for (const parameter of [
    "model=claude-haiku-4.5", "mode=relative", "scale=linear", "ranges=shown", "order=slowest",
  ]) {
    expect(backHref).toContain(parameter);
  }
  await back.click();
  await expect(performanceLink).toHaveClass(/active/);
  await expect(page.getByRole("checkbox", { name: "Show measurement ranges" })).toBeChecked();

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: /Export active records/ }).click();
  expect((await downloadPromise).suggestedFilename()).toBe("llm-eval-performance-cell.csv");

  await page.getByRole("combobox", { name: "Benchmark" }).selectOption("nbody");
  await expect(page).toHaveURL(/benchmark=nbody/);
  await expect(page).toHaveURL(/backend=omp/);
  await page.goBack();
  await expect(page.getByRole("combobox", { name: "Benchmark" })).toHaveValue("floydwarshall");
  await expect(page.getByRole("combobox", { name: "Target" })).toHaveValue("omp");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => window.innerWidth),
  );
  expect(problems).toEqual([]);
});

test("score and cost recomputes model aggregates from frozen pricing", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/cost");

  const costLink = page.getByRole("link", { name: "Cost Efficiency" });
  await expect(costLink).toHaveClass(/active/);
  await expect(page.getByRole("heading", { name: "Cost Efficiency" })).toBeAttached();
  const summary = page.getByLabel("Current cost efficiency selection summary");
  await expect(summary.getByText("14", { exact: true })).toBeVisible();
  await expect(summary.getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await expect(summary.getByText(/3[,.]077/, { exact: true })).toBeVisible();
  await expect(page.getByRole("combobox", { name: "Cost scale" })).toHaveValue("log");

  const chart = page.locator(".cost-analysis .chart");
  await expect(chart.locator("svg.marks")).toBeVisible();
  const points = chart.locator(".cost_points path");
  await expect(points).toHaveCount(14);
  const labels = chart.locator(".cost_labels text");
  await expect(labels).toHaveCount(14);
  await expect(labels.filter({ hasText: "GPT-5.6 Luna Medium" })).toHaveCount(1);
  await expect(labels.filter({ hasText: /GPT-5\.6 Luna (Low|XHigh)/ })).toHaveCount(0);

  const visibleLabelCount = await labels.evaluateAll((elements) => elements.filter((element) => {
    const style = getComputedStyle(element);
    const bounds = element.getBoundingClientRect();
    return style.opacity !== "0" && style.visibility !== "hidden" && bounds.width > 0 && bounds.height > 0;
  }).length);
  expect(visibleLabelCount).toBe(14);

  await points.first().hover({ force: true });
  const tooltip = page.locator("#vg-tooltip-element");
  await expect(tooltip).toBeVisible();
  for (const field of [
    "Mean score", "Estimated mean cost", "Runs", "Mean tokens", "Rates (USD/M tokens)",
    "Pricing profile", "Provider", "Quantization", "Pricing date", "Sources",
  ]) {
    await expect(tooltip).toContainText(field);
  }
  await expect(tooltip).not.toContainText("Cost method");
  await expect(tooltip).not.toContainText("Pricing match");
  await expect(tooltip.locator("tr")).toHaveCount(11);
  const compactTooltip = await tooltip.evaluate((element) => ({
    left: element.getBoundingClientRect().left,
    right: element.getBoundingClientRect().right,
    top: element.getBoundingClientRect().top,
    width: element.getBoundingClientRect().width,
    height: element.getBoundingClientRect().height,
    viewportWidth: window.innerWidth,
  }));
  expect(compactTooltip.width).toBeLessThan(560);
  expect(compactTooltip.width).toBeLessThanOrEqual(compactTooltip.viewportWidth - 8);
  expect(compactTooltip.left).toBeGreaterThanOrEqual(0);
  expect(compactTooltip.right).toBeLessThanOrEqual(compactTooltip.viewportWidth);
  if (compactTooltip.viewportWidth <= 600) expect(compactTooltip.top).toBeGreaterThanOrEqual(43);
  expect(compactTooltip.height).toBeLessThan(420);
  await page.mouse.move(1, 1);

  await page.getByRole("combobox", { name: "Cost scale" }).selectOption("linear");
  await expect(page).toHaveURL(/scale=linear/);
  await expect(page.getByText("Estimated API cost per run (USD)", { exact: true })).toBeVisible();
  await page.goBack();
  await expect(page.getByRole("combobox", { name: "Cost scale" })).toHaveValue("log");
  await page.goForward();
  await expect(page.getByRole("combobox", { name: "Cost scale" })).toHaveValue("linear");

  const benchmarkMenu = page.locator(".filter-menu").nth(1);
  await benchmarkMenu.locator("summary").click();
  await benchmarkMenu.getByRole("checkbox", { name: "Black Scholes" }).click();
  await page.mouse.click(4, 400);
  await expect(benchmarkMenu).not.toHaveAttribute("open", "");
  const backendMenu = page.locator(".filter-menu").nth(2);
  await backendMenu.locator("summary").click();
  await backendMenu.getByRole("checkbox", { name: "OpenMP" }).click();
  await expect(page).toHaveURL(/benchmark=black-scholes/);
  await expect(page).toHaveURL(/backend=omp/);
  await expect(summary.getByText("70", { exact: true })).toHaveCount(2);
  await page.getByRole("button", { name: /Reset/ }).click();
  await expect(page).toHaveURL(/#\/cost$/);
  await expect(page.getByRole("combobox", { name: "Cost scale" })).toHaveValue("log");

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await expect(page).toHaveURL(/model-set=all/);
  await expect(summary.getByText("21", { exact: true })).toBeVisible();
  await expect(summary.getByText(/4[,.]620/, { exact: true })).toBeVisible();
  await expect(summary.getByText(/4[,.]617/, { exact: true })).toBeVisible();
  await expect(points).toHaveCount(21);
  await expect(labels).toHaveCount(21);
  await expect(labels.filter({ hasText: /Qwen 3\.6 .*Pi-T/ })).toHaveCount(1);

  const allLabelLayout = await labels.evaluateAll((elements) => {
    const visible = elements.filter((element) => {
      const style = getComputedStyle(element);
      const bounds = element.getBoundingClientRect();
      return style.opacity !== "0" && style.visibility !== "hidden" && bounds.width > 0 && bounds.height > 0;
    });
    const bounds = visible.map((element) => ({
      label: element.textContent,
      rect: element.getBoundingClientRect(),
    }));
    const materialOverlaps: Array<[string | null, string | null]> = [];
    for (let left = 0; left < bounds.length; left += 1) {
      for (let right = left + 1; right < bounds.length; right += 1) {
        const overlapWidth = Math.min(bounds[left].rect.right, bounds[right].rect.right)
          - Math.max(bounds[left].rect.left, bounds[right].rect.left);
        const overlapHeight = Math.min(bounds[left].rect.bottom, bounds[right].rect.bottom)
          - Math.max(bounds[left].rect.top, bounds[right].rect.top);
        if (overlapWidth > 2 && overlapHeight > 2) {
          materialOverlaps.push([bounds[left].label, bounds[right].label]);
        }
      }
    }
    return { visibleCount: visible.length, materialOverlaps };
  });
  expect(allLabelLayout).toEqual({ visibleCount: 21, materialOverlaps: [] });

  const exportPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: /Export aggregates/ }).click();
  expect((await exportPromise).suggestedFilename()).toBe("llm-eval-score-cost.csv");
  await page.getByText("Accessible cost efficiency table", { exact: true }).click();
  const pricingSource = page.locator(".cost-data tbody tr").first().getByRole("link", { name: "Pricing source" });
  await expect(pricingSource).toHaveAttribute("target", "_blank");

  const firstPoint = points.first();
  await expect(firstPoint).toHaveAttribute("tabindex", "0");
  await firstPoint.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/runs\?model=/);
  await expect(page.getByRole("heading", { name: /matching runs/ })).toBeVisible();
  await page.goBack();
  await expect(costLink).toHaveClass(/active/);

  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => window.innerWidth),
  );
  expect(problems).toEqual([]);
});

test.describe("localized duration labels", () => {
  test.use({ locale: "de-DE" });

  test("uses the same millisecond representation in model, median, and run tooltips", async ({ page }) => {
    const problems = watchPage(page);
    await goto(page, "/performance");

    const chart = page.locator(".performance-analysis .chart");
    const tooltip = page.locator("#vg-tooltip-element");
    const expectedMedian = "1.278 ms";

    const modelLabel = chart.locator(".mark-text.role-mark text")
      .filter({ hasText: /^GPT-5\.6 Sol Medium$/ });
    await modelLabel.hover({ force: true });
    await expect(tooltip).toContainText(expectedMedian);
    await page.mouse.move(1, 1);

    await chart.locator(".performance_model_medians_marks path").first().hover({ force: true });
    await expect(tooltip).toContainText(expectedMedian);
    await page.mouse.move(1, 1);

    const firstRun = chart.locator('svg [role="button"][aria-label^="Run "]').first();
    const runMedian = await firstRun.evaluate((mark) => {
      const sceneItem = (mark as SVGElement & { __data__?: { datum?: Record<string, unknown> } }).__data__;
      return sceneItem?.datum?.medianMs;
    });
    expect(typeof runMedian).toBe("number");
    const expectedRunMedian = `${Number(runMedian).toLocaleString("de-DE", { maximumFractionDigits: 3 })} ms`;
    await firstRun.hover({ force: true });
    await expect(tooltip).toContainText(expectedRunMedian);
    expect(problems).toEqual([]);
  });
});

test("run detail keeps all models and highlights its model in the performance cell", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/runs?model-set=all&q=gpt-5.6-sol-xhigh");
  await expect(page.getByRole("heading", { name: /matching runs/ })).toBeVisible();
  const sourceRun = page.locator(".run-id-link").filter({ hasText: "gpt-5.6-sol-xhigh" }).first();
  await expect(sourceRun).toBeVisible();
  await sourceRun.click();

  const performanceLink = page.getByRole("link", { name: /Performance in this benchmark cell/ });
  const performanceHref = await performanceLink.getAttribute("href");
  expect(performanceHref).toContain("model-set=all");
  expect(performanceHref).toContain("focus=gpt-5.6-sol-xhigh");
  await performanceLink.click();

  const performanceParams = await page.evaluate(() => {
    const query = new URLSearchParams(location.hash.split("?")[1] ?? "");
    return {
      modelSet: query.get("model-set"),
      focus: query.get("focus"),
      benchmark: query.get("benchmark"),
      backend: query.get("backend"),
    };
  });
  expect(performanceParams).toMatchObject({
    modelSet: "all",
    focus: "gpt-5.6-sol-xhigh",
  });
  expect(performanceParams.benchmark).toBeTruthy();
  expect(performanceParams.backend).toBeTruthy();
  const selectionSummary = page.getByLabel("Current performance selection summary");
  await expect(selectionSummary.getByText("21", { exact: true })).toBeVisible();

  const chart = page.locator(".performance-analysis .chart");
  const focusedRow = chart.locator(".performance_focused_row_marks path");
  await expect(focusedRow).toHaveCount(1);
  const focusedLabel = chart.locator(".mark-text.role-mark text").filter({ hasText: /^GPT-5\.6 Sol XHigh$/ });
  await expect(focusedLabel).toBeVisible();
  const focusedBounds = await focusedRow.boundingBox();
  const labelBounds = await focusedLabel.boundingBox();
  expect(focusedBounds).not.toBeNull();
  expect(labelBounds).not.toBeNull();
  const labelCenter = labelBounds!.y + labelBounds!.height / 2;
  expect(labelCenter).toBeGreaterThan(focusedBounds!.y);
  expect(labelCenter).toBeLessThan(focusedBounds!.y + focusedBounds!.height);

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "Default" }).click();
  await expect(page).not.toHaveURL(/focus=/);
  await expect(selectionSummary.getByText("14", { exact: true })).toBeVisible();
  await expect(focusedRow).toHaveCount(0);
  expect(problems).toEqual([]);
});

test("timing-fixed runs expose corrected and original source revisions", async ({ page }) => {
  const problems = watchPage(page);
  const runId = "black-scholes_claude-haiku-4.5_mpi_r1";
  const correctedCommit = "e897bbe48e877ecbd8873ee1c666b6f394c0344b";
  const originalCommit = "e8d10c43d7fcdca42862537b0eb7d0d5fab6da66";

  await goto(page, `/runs?q=${runId}`);
  await expect(page.getByRole("heading", { name: "1 matching runs" })).toBeVisible();
  await expect(page.getByText("Timing fixed", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: `Open timing-corrected source for ${runId}` }))
    .toHaveAttribute("href", new RegExp(`/tree/${correctedCommit}/`));
  await page.getByRole("link", { name: runId, exact: true }).click();

  await expect(page.getByRole("link", { name: /Timing-corrected source directory/ }))
    .toHaveAttribute("href", new RegExp(`/tree/${correctedCommit}/`));
  await expect(page.getByRole("link", { name: /Original generated source directory/ }))
    .toHaveAttribute("href", new RegExp(`/tree/${originalCommit}/`));
  await expect(page.getByText(/missing rank aggregation, rank local timing/)).toBeVisible();
  expect(problems).toEqual([]);
});

test("winning implementation analysis renders after run details at desktop and mobile widths", async ({ page }, testInfo) => {
  const problems = watchPage(page);
  const runId = "floydwarshall_gpt-5.6-sol-xhigh_mpi_r5";

  await goto(page, `/run/${runId}`);
  await expect(page.getByRole("heading", { name: runId, level: 1 })).toBeVisible();
  await expect(page.getByRole("heading", { name: runId })).toHaveCount(1);
  const analysisCard = page.getByRole("region", { name: "Winning implementation analysis" });
  await expect(analysisCard).toBeVisible();
  await expect(analysisCard.getByRole("heading", { name: "Controlled evidence", level: 3 })).toBeVisible();
  await expect(analysisCard.getByText(/dominant difference is a simpler phase-three local update loop/)).toBeVisible();
  await expect(analysisCard.getByRole("table")).toBeVisible();
  await expect(analysisCard.getByRole("row", { name: /Original 256-column subdivision/ })).toBeVisible();

  const layout = await page.evaluate(() => {
    const details = document.querySelector<HTMLElement>(".detail-grid")!.getBoundingClientRect();
    const card = document.querySelector<HTMLElement>(".implementation-analysis-card")!.getBoundingClientRect();
    const table = document.querySelector<HTMLElement>(".implementation-analysis-table")!;
    return {
      detailsLeft: details.left,
      detailsRight: details.right,
      detailsBottom: details.bottom,
      cardLeft: card.left,
      cardRight: card.right,
      cardTop: card.top,
      tableClientWidth: table.clientWidth,
      tableScrollWidth: table.scrollWidth,
    };
  });
  expect(Math.abs(layout.cardLeft - layout.detailsLeft)).toBeLessThan(1);
  expect(Math.abs(layout.cardRight - layout.detailsRight)).toBeLessThan(1);
  expect(layout.cardTop).toBeGreaterThan(layout.detailsBottom);
  if (testInfo.project.name === "mobile") {
    expect(layout.tableScrollWidth).toBeGreaterThan(layout.tableClientWidth);
  } else {
    expect(layout.tableScrollWidth).toBeLessThanOrEqual(layout.tableClientWidth + 1);
  }
  expect(problems).toEqual([]);
});

test("complexity recomputes benchmark and target distributions and opens their runs", async ({ page }, testInfo) => {
  const problems = watchPage(page);
  await goto(page, "/complexity");
  const complexityLink = page.getByRole("link", { name: "Complexity" });
  await expect(complexityLink).toHaveClass(/active/);
  await expect(page.getByRole("heading", { name: "Benchmark / Target complexity" })).toBeVisible();
  const selectionSummary = page.getByLabel("Current complexity selection summary");
  await expect(selectionSummary.getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("6.45", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Export chart")).toHaveCount(2);

  const benchmarkCategories = page.locator('.benchmark-complexity svg [role="button"][aria-label^="Benchmark "]');
  const targetCategories = page.locator('.target-complexity svg [role="button"][aria-label^="Target "]');
  await expect(benchmarkCategories.first()).toBeVisible();
  await expect(targetCategories.first()).toBeVisible();
  expect(await benchmarkCategories.count()).toBe(11);
  expect(await targetCategories.count()).toBe(4);

  const gridColumns = await page.locator(".complexity-grid").evaluate((grid) =>
    getComputedStyle(grid).gridTemplateColumns.split(" ").filter(Boolean).length);
  expect(gridColumns).toBe(testInfo.project.name === "mobile" ? 1 : 2);

  const chartLayout = await page.evaluate(() => {
    const benchmarkChart = document.querySelector<HTMLElement>(".benchmark-complexity .chart")!;
    const benchmarkSvg = benchmarkChart.querySelector<SVGSVGElement>("svg")!;
    const benchmarkLabels = [...document.querySelectorAll<SVGTextElement>(
      ".benchmark-complexity .role-row-header text",
    )].map((label) => label.getBoundingClientRect());
    const benchmarkAreas = [...document.querySelectorAll<SVGPathElement>(
      ".benchmark-complexity .mark-area path",
    )].map((area) => area.getBoundingClientRect());
    const targetChart = document.querySelector<HTMLElement>(".target-complexity .chart")!;
    const targetSvg = targetChart.querySelector<SVGSVGElement>("svg")!;
    const targetLabelTop = Math.min(...[...document.querySelectorAll<SVGTextElement>(
      ".target-complexity .role-column-footer text",
    )].map((label) => label.getBoundingClientRect().top));
    const targetPlotBottom = Math.max(...[...document.querySelectorAll<SVGPathElement>(
      ".target-complexity .mark-area path",
    )].map((area) => area.getBoundingClientRect().bottom));
    const footnote = document.querySelector<HTMLElement>(".chart-footnote")!;
    const centerOffset = (outer: DOMRect, inner: DOMRect) =>
      Math.abs((inner.left + inner.width / 2) - (outer.left + outer.width / 2));
    return {
      benchmarkClientWidth: benchmarkChart.clientWidth,
      benchmarkScrollWidth: benchmarkChart.scrollWidth,
      benchmarkLabelSpread: Math.max(...benchmarkLabels.map((label) => label.right))
        - Math.min(...benchmarkLabels.map((label) => label.right)),
      benchmarkVerticalOffset: Math.max(...benchmarkLabels.map((label, index) =>
        Math.abs((label.top + label.height / 2) - (benchmarkAreas[index]!.top + benchmarkAreas[index]!.height / 2)))),
      benchmarkCenterOffset: centerOffset(benchmarkChart.getBoundingClientRect(), benchmarkSvg.getBoundingClientRect()),
      targetCenterOffset: centerOffset(targetChart.getBoundingClientRect(), targetSvg.getBoundingClientRect()),
      targetLabelGap: targetLabelTop - targetPlotBottom,
      quartileRules: document.querySelectorAll('.complexity-grid svg [stroke-dasharray="2,2"]').length,
      targetMedianRules: document.querySelectorAll(
        '.target-complexity .role-mark line[aria-label^="Max of median"]',
      ).length,
      targetGrandMeanRules: document.querySelectorAll(
        '.target-complexity .role-mark line[aria-label*="Grand mean"]',
      ).length,
      footnoteFontSize: Number.parseFloat(getComputedStyle(footnote).fontSize),
    };
  });
  expect(chartLayout.benchmarkScrollWidth).toBeLessThanOrEqual(chartLayout.benchmarkClientWidth);
  expect(chartLayout.benchmarkLabelSpread).toBeLessThan(2);
  expect(chartLayout.benchmarkVerticalOffset).toBeLessThan(2);
  expect(chartLayout.benchmarkCenterOffset).toBeLessThan(1);
  expect(chartLayout.targetCenterOffset).toBeLessThan(1);
  expect(chartLayout.targetLabelGap).toBeGreaterThanOrEqual(2);
  expect(chartLayout.quartileRules).toBe(0);
  expect(chartLayout.targetMedianRules).toBe(0);
  expect(chartLayout.targetGrandMeanRules).toBe(4);
  expect(chartLayout.footnoteFontSize).toBeGreaterThanOrEqual(13.5);

  await benchmarkCategories.first().hover({ force: true });
  const tooltip = page.locator("#vg-tooltip-element");
  await expect(tooltip).toBeVisible();
  await expect(tooltip).toContainText("Runs");
  await expect(tooltip).toContainText("Mean");
  await expect(tooltip).toContainText("Q1");
  await expect(tooltip).toContainText("Median");
  await expect(tooltip).toContainText("Q3");
  await expect(tooltip).toContainText("Grand mean");
  await page.mouse.move(1, 1);

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("checkbox", { name: "Haiku 4.5" }).click();
  await expect(page).toHaveURL(/model=claude-haiku-4.5/);
  await page.locator(".brand-name").click();
  await expect(modelMenu).not.toHaveAttribute("open", "");
  await expect(selectionSummary.getByText("220", { exact: true })).toBeVisible();
  await expect(selectionSummary.getByText("5.52", { exact: true })).toBeVisible();

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: /Export active records/ }).click();
  expect((await downloadPromise).suggestedFilename()).toBe("llm-eval-complexity-selection.csv");

  const selectedBenchmark = page.locator('.benchmark-complexity svg [role="button"][aria-label^="Benchmark "]').first();
  await selectedBenchmark.focus();
  await expect(selectedBenchmark).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/runs\?model=claude-haiku-4.5&benchmark=/);
  await expect(page.getByRole("heading", { name: "Runs", exact: true })).toBeVisible();
  await page.goBack();
  await expect(complexityLink).toHaveClass(/active/);
  await expect(selectionSummary.getByText("220", { exact: true })).toBeVisible();

  await page.locator(".target-complexity .mark-area path").first().click({ force: true });
  await expect(page).toHaveURL(/#\/runs\?model=claude-haiku-4.5&backend=/);
  await expect(page.getByRole("heading", { name: "Runs", exact: true })).toBeVisible();
  expect(problems).toEqual([]);
});

test("runs combine outcome filters, paginate, and retain context through detail", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/runs?model=gpt-4.1&band=invalid");
  await expect(page.getByRole("heading", { name: "127 matching runs" })).toBeVisible();

  await page.getByRole("combobox", { name: "Validation" }).selectOption("failed");
  await page.getByRole("combobox", { name: "Exact score" }).selectOption("4");
  await expect(page).toHaveURL(/validation=failed/);
  await expect(page).toHaveURL(/score=4/);
  await expect(page.getByRole("heading", { name: /matching runs/ })).toBeVisible();

  await page.getByRole("combobox", { name: "Exact score" }).selectOption("");
  await page.getByRole("combobox", { name: "Validation" }).selectOption("all");
  await page.getByRole("button", { name: "Next →" }).click();
  await expect(page).toHaveURL(/page=2/);
  await expect(page.getByText("Page 2 of 3")).toBeVisible();

  const firstRun = page.locator(".run-id-link").first();
  const runId = (await firstRun.textContent())!;
  await firstRun.click();
  await expect(page.getByRole("heading", { name: runId })).toBeVisible();
  await expect(page.getByText("Tokens and cost", { exact: true })).toBeVisible();
  const tokenConsumption = page.getByLabel("Token consumption");
  await expect(tokenConsumption).toBeVisible();
  await expect(tokenConsumption).toContainText("Priced token volume");
  await expect(tokenConsumption).toContainText("Input tokens (cache included)");
  await expect(tokenConsumption).toContainText("Cached input tokens");
  await expect(tokenConsumption).toContainText("Output tokens");
  await expect(page.getByRole("link", { name: /This model in Cost Efficiency/ })).toHaveAttribute("href", /#\/cost\?/);
  const sourceLink = page.getByRole("link", { name: /Generated source directory/ });
  await expect(sourceLink).toHaveAttribute("href", /\/tree\/[0-9a-f]{40}\//);
  await expect(sourceLink).toHaveAttribute("target", "_blank");
  await expect(page.getByRole("link", { name: /Validation JSONL evidence/ })).toHaveAttribute("href", /#L\d+$/);
  await expect(page.getByRole("link", { name: /Back to matching runs/ })).toHaveAttribute("href", /page=2/);
  await page.getByRole("link", { name: /Back to matching runs/ }).click();
  await expect(page.getByText("Page 2 of 3")).toBeVisible();
  expect(problems).toEqual([]);
});

test("run detail distinguishes combined and separately cached token records", async ({ page }) => {
  const problems = watchPage(page);

  await goto(page, "/runs?model=gpt-5.6-sol-medium");
  await expect(page.getByRole("heading", { name: "220 matching runs" })).toBeVisible();
  await page.locator(".run-id-link").first().click();
  const combinedTokens = page.getByLabel("Token consumption");
  await expect(combinedTokens).toContainText("Combined tokens");
  await expect(combinedTokens).not.toContainText("Cached input tokens");
  await expect(page.getByRole("heading", { name: /estimated API cost$/ })).toBeVisible();

  await goto(page, "/runs?model=qwen-3.6-27B-udq4-pi-t");
  await expect(page.getByRole("heading", { name: "220 matching runs" })).toBeVisible();
  await page.locator(".run-id-link").first().click();
  const splitTokens = page.getByLabel("Token consumption");
  await expect(splitTokens).toContainText("Priced token volume");
  await expect(splitTokens).toContainText("Uncached input tokens");
  await expect(splitTokens).toContainText("Cached input tokens");
  await expect(splitTokens).toContainText("Output tokens");
  expect(problems).toEqual([]);
});

test("Pages-safe routes and information pages remain functional", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/performance");
  await expect(page).toHaveURL(/#\/performance$/);
  await expect(page.getByRole("link", { name: "Performance" })).toHaveClass(/active/);
  await expect(page.getByText("Next", { exact: true })).toHaveCount(0);
  const footer = page.locator(".site-footer");
  await expect(footer).not.toContainText("Client-only");
  const snapshot = footer.getByRole("link", { name: /Snapshot [0-9a-f]{9}/ });
  await expect(snapshot).toHaveAttribute("href", /\/tree\/[0-9a-f]{40}$/);
  const snapshotCommit = (await snapshot.getAttribute("href"))!.split("/").at(-1)!;
  await expect(snapshot.locator("code")).toHaveText(snapshotCommit.slice(0, 9));
  await expect(snapshot.locator("time")).toHaveText("2026-08-25 02:50:29 UTC+02:00");
  await expect(snapshot.locator("time")).toHaveAttribute("datetime", "2026-08-25T02:50:29+02:00");
  await expect(page.locator(".primary-nav")).not.toContainText("Snapshot");
  await goto(page, "/methodology");
  await expect(page.getByRole("heading", { name: "Methodology" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Agent harnesses" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Five sequential stages" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Recorded local execution system" })).toBeVisible();
  await expect(page.getByText(/five independent agent invocations were performed/)).toBeVisible();
  await expect(page.getByRole("heading", { name: "Current dataset" })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "GitHub Copilot CLI", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "pi", exact: true })).toBeVisible();
  await expect(page.locator('[aria-labelledby="method-system"] > p').filter({ hasText: "128 physical cores" })).toBeVisible();
  await expect(page.getByText("128 ranks, 64 per socket, 1 physical core per rank", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Experiment harness configuration/ })).toHaveAttribute("href", /\/blob\/[0-9a-f]{40}\/experiment\.rb$/);
  await expect(page.getByRole("link", { name: /Threshold review/ })).toHaveAttribute("href", /local_scoring_threshold_review\.yaml$/);
  await expect(page.getByRole("heading", { name: "Frozen API pricing" })).toBeVisible();
  await expect(page.getByText(/Shown API cost is based on API rates/)).toBeVisible();
  await expect(page.getByRole("link", { name: "Cost estimation generator" })).toHaveAttribute("href", /all_models_score_vs_cost\.py$/);
  await expect(page.getByRole("link", { name: "Frozen pricing profiles" })).toHaveAttribute("href", /4d_all_models_score_vs_cost\.csv$/);
  await goto(page, "/cite");
  await expect(page.getByRole("heading", { name: "Citation" })).toBeAttached();
  await expect(page.getByRole("heading", { name: "Cite this work" })).toHaveCount(0);
  await expect(page.getByText("Please Cite the following paper if you use this work")).toBeVisible();
  await expect(page.getByRole("link", { name: "Cite" })).toHaveClass(/active/);
  await expect(page.getByRole("link", { name: "Peter Thoman" })).toHaveAttribute("href", "https://dps.uibk.ac.at/~petert");
  await expect(page.getByRole("link", { name: "Philipp Gschwandtner" })).toHaveAttribute("href", "https://dps.uibk.ac.at/~philipp");
  await expect(page.getByRole("link", { name: "Evaluating the Parallelization Capabilities of State-of-the-Art Agentic Large Language Models" })).toHaveAttribute(
    "href",
    "https://link.springer.com/chapter/10.1007/978-3-032-35248-4_2",
  );
  await expect(page.getByLabel("Citation scope")).toContainText("extended dataset");
  await expect(page.getByLabel("Citation scope")).toContainText("slightly revised methodology");
  await expect(page.getByRole("link", { name: "10.1007/978-3-032-35248-4_2" })).toHaveAttribute("href", "https://doi.org/10.1007/978-3-032-35248-4_2");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => window.innerWidth),
  );
  await goto(page, "/run/not-a-run");
  await expect(page.getByRole("heading", { name: "No run has this identifier." })).toBeVisible();

  const origins = await page.evaluate(() => performance.getEntriesByType("resource").map((entry) => new URL(entry.name).origin));
  expect([...new Set(origins)]).toEqual(["http://127.0.0.1:4173"]);
  expect(problems).toEqual([]);
});

test("dark selects and chart tooltips retain readable compact styling", async ({ page }, testInfo) => {
  const problems = watchPage(page);
  await page.emulateMedia({ colorScheme: "dark" });
  await goto(page, "/tiers");
  await expect(page.locator("body")).toHaveCSS("font-family", /Roboto Condensed Variable/);
  await expect(page.locator(".chart svg text").first()).toHaveCSS("font-family", /Roboto Condensed Variable/);
  const order = page.getByRole("combobox", { name: "Order" });
  await expect(order).toBeVisible();
  const colors = await order.evaluate((select) => {
    const selectStyle = getComputedStyle(select);
    const optionStyle = getComputedStyle(select.querySelector("option")!);
    return {
      selectBackground: selectStyle.backgroundColor,
      selectColor: selectStyle.color,
      optionBackground: optionStyle.backgroundColor,
      optionColor: optionStyle.color,
    };
  });
  expect(colors).toEqual({
    selectBackground: "rgb(24, 33, 38)",
    selectColor: "rgb(237, 240, 235)",
    optionBackground: "rgb(32, 42, 48)",
    optionColor: "rgb(237, 240, 235)",
  });

  await page.locator(".mark-rect path").first().hover({ force: true });
  const tooltip = page.locator("#vg-tooltip-element");
  await expect(tooltip).toBeVisible();
  await expect(tooltip).toContainText("Tier");
  await expect(tooltip).not.toContainText("Agent harness");
  await expect(tooltip).not.toContainText("Invocation");

  const modelLabel = page.locator(".chart svg g.mark-text.role-mark text").filter({ hasText: /^GPT-4\.1$/ }).first();
  await expect(modelLabel).toBeVisible();
  await modelLabel.hover({ force: true });
  await expect(tooltip).toContainText("Model");
  await expect(tooltip).toContainText("Agent harness");
  await expect(tooltip).toContainText("GitHub Copilot CLI");
  await expect(tooltip).toContainText("Invocation");
  await expect(tooltip).not.toContainText("Tier");
  await expect(tooltip).toHaveCSS("font-size", "14px");
  const tooltipTheme = await tooltip.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      background: style.backgroundColor,
      color: style.color,
      borderColor: style.borderColor,
    };
  });
  expect(tooltipTheme).toEqual({
    background: "rgb(32, 42, 48)",
    color: "rgb(237, 240, 235)",
    borderColor: "rgb(74, 91, 97)",
  });
  const chartFontSizes = await page.locator(".chart svg text").evaluateAll((nodes) =>
    [...new Set(nodes.map((node) => getComputedStyle(node).fontSize))]);
  expect(chartFontSizes).toContain(testInfo.project.name === "desktop" ? "14px" : "12px");
  await expect(page.locator(".footer-dps-link")).toHaveCSS("background-color", "rgb(255, 255, 255)");
  await expect(page.locator(".footer-dps-link")).toHaveCSS("border-radius", "4.8px");
  await expect(page.locator(".site-footer")).toHaveCSS("flex-direction", "row");
  await expect(page.getByRole("link", { name: "Tiered Success" })).toHaveCSS(
    "font-size",
    testInfo.project.name === "desktop" ? "14.08px" : "12.8px",
  );
  const layout = await tooltip.evaluate((element) => ({
    width: element.getBoundingClientRect().width,
    rowHeights: [...element.querySelectorAll("tr")].map((row) => row.getBoundingClientRect().height),
    cellBorderWidths: [...element.querySelectorAll("td")].map((cell) => getComputedStyle(cell).borderBottomWidth),
  }));
  expect(layout.width).toBeLessThan(480);
  expect(Math.max(...layout.rowHeights)).toBeLessThan(34);
  expect(new Set(layout.cellBorderWidths)).toEqual(new Set(["0px"]));
  expect(problems).toEqual([]);
});
