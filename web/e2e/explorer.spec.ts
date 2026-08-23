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

test("tier overview filters, exports, and drills into its source runs", async ({ page }) => {
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
  await expect(page.getByText(/4[,.]620/, { exact: true })).toBeVisible();
  await expect(page.locator(".chart svg.marks")).toBeVisible();
  await expect(page.locator(".mark-rect path").first()).toBeVisible();

  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();

  const aboutMenu = page.locator(".about-menu");
  const aboutSummary = aboutMenu.locator("summary");
  await aboutSummary.click();
  await expect(aboutMenu).toHaveAttribute("open", "");
  await expect(aboutMenu.getByRole("link", { name: "Citation information" })).toHaveAttribute("href", "#/cite");
  await page.getByRole("link", { name: "LLM Autoparallelization Benchmark home" }).click();
  await expect(aboutMenu).not.toHaveAttribute("open", "");
  await aboutSummary.click();
  await page.keyboard.press("Escape");
  await expect(aboutMenu).not.toHaveAttribute("open", "");
  await expect(aboutSummary).toBeFocused();

  const modelMenu = page.locator(".filter-menu").first();
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

test("all Pages-safe routes have deliberate states", async ({ page }) => {
  const problems = watchPage(page);
  for (const route of ["/scores", "/complexity", "/performance"]) {
    await goto(page, route);
    await expect(page.getByRole("heading", { name: "This analysis view is intentionally staged." })).toBeVisible();
  }
  await goto(page, "/methodology");
  await expect(page.getByRole("heading", { name: "Methodology" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Agent harnesses" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Five sequential stages" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Recorded local execution system" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Codex CLI", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "GitHub Copilot CLI", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "pi", exact: true })).toBeVisible();
  await expect(page.locator('[aria-labelledby="method-system"] > p').filter({ hasText: "128 physical cores" })).toBeVisible();
  await expect(page.getByText("128 ranks, 64 per socket, 1 physical core per rank", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Experiment harness configuration/ })).toHaveAttribute("href", /\/blob\/[0-9a-f]{40}\/experiment\.rb$/);
  await expect(page.getByRole("link", { name: /Threshold review/ })).toHaveAttribute("href", /local_scoring_threshold_review\.yaml$/);
  await goto(page, "/cite");
  await expect(page.getByRole("heading", { name: "Cite this work" })).toBeVisible();
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
