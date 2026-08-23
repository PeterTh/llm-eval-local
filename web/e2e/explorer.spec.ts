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
  await expect(selectionSummary.getByText("6.44", { exact: true })).toBeVisible();

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
  await expect(selectionSummary.getByText("6.60", { exact: true })).toBeVisible();
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
  const scoresLink = page.getByRole("link", { name: "Model scores" });
  await expect(scoresLink).toHaveClass(/active/);
  await expect(page.getByRole("heading", { name: "Model scores" })).toBeVisible();
  await expect(page.getByLabel("Current score selection summary").getByText(/3[,.]080/, { exact: true })).toBeVisible();
  await expect(page.locator(".score-analysis .chart svg.marks")).toBeVisible();
  await expect(page.locator(".score-analysis .mark-rect path").first()).toBeVisible();

  const modelMenu = page.locator(".filter-menu").first();
  await modelMenu.locator("summary").click();
  await modelMenu.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("checkbox", { name: "Haiku 4.5" }).click();
  await expect(page).toHaveURL(/model=claude-haiku-4.5/);
  await expect(page.getByLabel("Current score selection summary").getByText("220", { exact: true })).toBeVisible();
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
  const back = page.getByRole("link", { name: /Back to model scores/ });
  await expect(back).toHaveAttribute("href", /#\/scores\?model=claude-haiku-4.5&sort=strongest/);
  await back.click();
  await expect(page.getByRole("link", { name: "Model scores", exact: true })).toHaveClass(/active/);
  await expect(page.getByLabel("Current score selection summary").getByText("220", { exact: true })).toBeVisible();
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
  await expect(selectionSummary.getByText("6.44", { exact: true })).toBeVisible();
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
  const sourceLink = page.getByRole("link", { name: /Generated source directory/ });
  await expect(sourceLink).toHaveAttribute("href", /\/tree\/[0-9a-f]{40}\//);
  await expect(sourceLink).toHaveAttribute("target", "_blank");
  await expect(page.getByRole("link", { name: /Validation JSONL evidence/ })).toHaveAttribute("href", /#L\d+$/);
  await expect(page.getByRole("link", { name: /Back to matching runs/ })).toHaveAttribute("href", /page=2/);
  await page.getByRole("link", { name: /Back to matching runs/ }).click();
  await expect(page.getByText("Page 2 of 3")).toBeVisible();
  expect(problems).toEqual([]);
});

test("Pages-safe routes and information pages remain functional", async ({ page }) => {
  const problems = watchPage(page);
  await goto(page, "/performance");
  await expect(page).toHaveURL(/#\/tiers$/);
  await expect(page.getByRole("link", { name: "Tiered Success" })).toHaveClass(/active/);
  await expect(page.getByText("Next", { exact: true })).toHaveCount(0);
  await expect(page.locator(".site-footer")).not.toContainText("Client-only");
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
  const chartFontSizes = await page.locator(".chart svg text").evaluateAll((nodes) =>
    [...new Set(nodes.map((node) => getComputedStyle(node).fontSize))]);
  expect(chartFontSizes).toContain(testInfo.project.name === "desktop" ? "14px" : "12px");
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
