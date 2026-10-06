import { readFile } from "node:fs/promises";
import { expect, test, type Page } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
test.use({ hasTouch: true });

const views = [
  { route: "cost", panel: ".cost-analysis", marks: ".cost_points path", decorations: ".cost_highlight_halos path", key: "highlight-model" },
  { route: "time", panel: ".time-analysis", marks: ".time_points path", decorations: ".time_highlight_halos path", key: "highlight-model" },
  { route: "tiers", panel: ".analysis-panel", marks: ".tiers_model_labels_marks text", decorations: ".tiers_highlight_rows_marks path", key: "highlight-model" },
  { route: "scores", panel: ".score-analysis", marks: ".score_model_labels_marks text", decorations: ".score_highlight_rows_marks path", key: "highlight-model" },
  { route: "complexity", panel: ".benchmark-complexity", marks: ".benchmark_means_marks path", decorations: ".benchmark_highlight_rows_marks path", key: "highlight-benchmark" },
  { route: "performance", panel: ".performance-analysis", marks: '[aria-label^="Run "]', decorations: ".performance_highlight_halos_marks path", key: "highlight-run" },
] as const;

const query = (page: Page) => new URLSearchParams(new URL(page.url()).hash.split("?")[1]);

for (const view of views) {
  test(`${view.route} highlights support selection, focus, themes and exports`, async ({ page }, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(`${basePath}#/${view.route}?model-set=all`);
    const panel = page.locator(view.panel).first();
    const marks = panel.locator(view.marks);
    await expect(marks.last()).toHaveAttribute("data-highlight-id", /.+/);
    const lastIndex = await marks.count() - 1;
    const first = marks.nth(lastIndex);
    const second = marks.nth(lastIndex - 1);
    const ids = [(await first.getAttribute("data-highlight-id"))!, (await second.getAttribute("data-highlight-id"))!];
    const mode = panel.getByRole("button", { name: "Highlight mode" });
    const exportButton = panel.getByRole("button", { name: "Export", exact: true });
    await expect(exportButton).toHaveAttribute("title", /CSV/);
    // Both actions occupy the same compact row, including at mobile width.
    expect(Math.abs((await mode.boundingBox())!.y - (await exportButton.boundingBox())!.y)).toBeLessThan(2);
    await mode.click();
    await first.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" }));
    if (testInfo.project.name === "mobile") await first.tap();
    else {
      await first.focus();
      await page.keyboard.press("Space");
      await expect(first).toBeFocused();
    }
    await expect(first).toHaveAttribute("aria-pressed", "true");
    expect(query(page).getAll(view.key)).toEqual([ids[0]]);
    await second.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" }));
    await second.focus();
    const beforeScroll = await page.evaluate(() => window.scrollY);
    await page.keyboard.press("Enter");
    await expect(second).toBeFocused();
    await expect(second).toHaveAttribute("aria-pressed", "true");
    expect(Math.abs(await page.evaluate(() => window.scrollY) - beforeScroll)).toBeLessThan(2);
    expect(query(page).getAll(view.key).sort()).toEqual([...ids].sort());
    await expect(panel.locator(view.decorations)).toHaveCount(2);
    await page.keyboard.press("Escape");
    await expect(mode).toHaveAttribute("aria-pressed", "false");
    await expect(panel.locator(view.decorations)).toHaveCount(2);

    for (const colorScheme of ["light", "dark"] as const) {
      if (testInfo.project.name === "mobile") await page.setViewportSize({ width: colorScheme === "dark" ? 320 : 390, height: 844 });
      await page.emulateMedia({ colorScheme });
      for (const scale of view.route === "cost" || view.route === "time" || view.route === "performance" ? ["linear", "log"] : [null]) {
        const params = query(page);
        if (scale) params.set("scale", scale);
        await page.goto(`${basePath}#/${view.route}?${params}`);
        await expect(panel.locator(view.decorations)).toHaveCount(2);
        await expect(marks.nth(lastIndex)).toHaveAttribute("aria-label", /Highlighted: Yes/);
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        await page.mouse.move(1, 1);
        await page.evaluate(() => { if (document.activeElement instanceof SVGElement) document.activeElement.blur(); });
        await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
        await page.screenshot({ path: testInfo.outputPath(`${view.route}-highlight-${colorScheme}-${scale ?? "rows"}.png`), fullPage: true, clip: (await panel.boundingBox())! });
      }
    }
    await first.hover({ force: true });
    await expect(page.locator("#vg-tooltip-element tr").filter({ hasText: "Highlighted" })).toContainText("Yes");
    await page.mouse.move(1, 1);
    await panel.getByLabel("Export chart").click();
    const svg = page.getByRole("link", { name: "Save as SVG" });
    await svg.dispatchEvent("mousedown", { button: 0 });
    await expect(svg).toHaveAttribute("href", /^blob:/);
    const downloading = page.waitForEvent("download");
    await svg.click();
    const exported = await readFile((await (await downloading).path())!, "utf8");
    expect(exported).toMatch(/highlight_(halos|rows)/);
    expect(exported).toContain("#f2b861");
    const png = page.getByRole("link", { name: "Save as PNG" });
    await png.dispatchEvent("mousedown", { button: 0 });
    await expect(png).toHaveAttribute("href", /^(blob:|data:image\/png)/);
    const amberPixels = await png.evaluate(async (link) => {
      const image = new Image();
      image.src = (link as HTMLAnchorElement).href;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      const context = canvas.getContext("2d")!;
      context.drawImage(image, 0, 0);
      const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
      let count = 0;
      for (let index = 0; index < pixels.length; index += 4) {
        if (pixels[index] === 242 && pixels[index + 1] === 184 && pixels[index + 2] === 97) count += 1;
      }
      return count;
    });
    expect(amberPixels).toBeGreaterThan(8);
    await panel.getByLabel("Export chart").click();
    await panel.getByRole("button", { name: "Clear highlights" }).click();
    await expect(panel.locator(view.decorations)).toHaveCount(0);
    expect(query(page).has(view.key)).toBe(false);
    expect(errors).toEqual([]);
  });
}

test("shared model highlights restore in a fresh context and survive navigation and filters", async ({ page, browser }) => {
  await page.goto(`${basePath}#/cost?model-set=all`);
  const point = page.locator(".cost_points path").last();
  await expect(point).toHaveAttribute("data-highlight-id", /.+/);
  const id = (await point.getAttribute("data-highlight-id"))!;
  const modelLabel = await point.evaluate((element) => (element as SVGElement & { __data__: { datum: { modelLabel: string } } }).__data__.datum.modelLabel);
  await page.getByRole("button", { name: "Highlight mode" }).click();
  await point.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator(".cost_highlight_halos path")).toHaveCount(1);
  await page.evaluate(() => {
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async (text: string) => { (window as unknown as { shared: string }).shared = text; } } });
  });
  await page.getByRole("button", { name: "Share view" }).click();
  const shared = await page.evaluate(() => (window as unknown as { shared: string }).shared);
  expect(shared).toBe(page.url());
  const recipientContext = await browser.newContext();
  try {
    const recipient = await recipientContext.newPage();
    await recipient.goto(shared);
    await expect(recipient.locator(".cost_highlight_halos path")).toHaveCount(1);
    await expect(recipient.getByRole("button", { name: "Highlight mode" })).toHaveAttribute("aria-pressed", "false");
  } finally { await recipientContext.close(); }
  for (const [label, selector] of [
    ["Time Efficiency", ".time_highlight_halos path"], ["Tiered Success", ".tiers_highlight_rows_marks path"],
    ["Model Scores", ".score_highlight_rows_marks path"], ["Cost Efficiency", ".cost_highlight_halos path"],
  ]) {
    await page.getByRole("link", { name: label!, exact: true }).click();
    await expect(page.locator(selector!)).toHaveCount(1);
    expect(query(page).getAll("highlight-model")).toEqual([id]);
    await expect(page.getByRole("button", { name: "Highlight mode" })).toHaveAttribute("aria-pressed", "false");
  }
  const menu = page.locator(".filter-menu").first();
  await menu.locator("summary").click();
  const anotherModel = await menu.getByRole("checkbox").evaluateAll((elements, highlightedLabel) => elements
    .map((element) => element.closest("label")!.textContent!.trim()).find((label) => label !== highlightedLabel)!, modelLabel);
  await menu.getByRole("checkbox", { name: anotherModel, exact: true }).click();
  await expect(menu.getByRole("checkbox", { name: anotherModel, exact: true })).toBeChecked();
  await page.keyboard.press("Escape");
  await expect(page.locator(".cost_highlight_halos path")).toHaveCount(0);
  await expect(page.getByRole("status")).toContainText("1 not shown");
  await page.getByRole("button", { name: /Reset/ }).click();
  expect(query(page).getAll("highlight-model")).toEqual([id]);
  await menu.locator("summary").click();
  await menu.getByRole("button", { name: "All", exact: true }).click();
  await page.keyboard.press("Escape");
  await expect(page.locator(".cost_highlight_halos path")).toHaveCount(1);
});

test("history, hidden IDs, and clearing preserve independent selections", async ({ page }) => {
  await page.goto(`${basePath}#/time?model-set=all&highlight-model=unknown%2F%3F%26%2B&highlight-run=stored-run&highlight-benchmark=stored-benchmark`);
  await expect(page.getByRole("status")).toContainText("1 highlighted · 1 not shown");
  const points = page.locator(".time_points path");
  await expect(points).toHaveCount(28);
  const first = points.last();
  const id = (await first.getAttribute("data-highlight-id"))!;
  await page.getByRole("button", { name: "Highlight mode" }).click();
  await first.focus();
  await page.keyboard.press("Enter");
  await expect(first).toHaveAttribute("aria-pressed", "true");
  await page.keyboard.press("Space");
  await expect(first).toHaveAttribute("aria-pressed", "false");
  await page.goBack();
  await expect(first).toHaveAttribute("aria-pressed", "true");
  expect(query(page).getAll("highlight-model")).toContain(id);
  await page.goForward();
  await expect(first).toHaveAttribute("aria-pressed", "false");
  await page.getByRole("button", { name: "Clear highlights" }).click();
  expect(query(page).has("highlight-model")).toBe(false);
  expect(query(page).get("highlight-run")).toBe("stored-run");
  expect(query(page).get("highlight-benchmark")).toBe("stored-benchmark");
  await page.goBack();
  await expect(page.getByRole("status")).toContainText("1 not shown");
});

for (const route of ["tiers", "scores"] as const) {
  test(`${route} data marks highlight the model row without opening records`, async ({ page }) => {
    await page.goto(`${basePath}#/${route}?model-set=all`);
    const mark = page.locator(route === "tiers" ? '[aria-roledescription="bar"]' : '.score-analysis [aria-roledescription="circle"]').first();
    await expect(mark).toBeVisible();
    const modelId = await mark.evaluate((element) => (element as SVGElement & { __data__: { datum: { modelId: string } } }).__data__.datum.modelId);
    await page.getByRole("button", { name: "Highlight mode" }).click();
    await mark.click({ force: true });
    await expect(page.getByRole("status")).toHaveText("1 highlighted");
    expect(query(page).getAll("highlight-model")).toEqual([modelId]);
    expect(new URL(page.url()).hash).toMatch(new RegExp(`^#/${route}\\?`));
  });
}

test("Complexity benchmark labels select by ID and retain focus", async ({ page }) => {
  await page.goto(`${basePath}#/complexity?model-set=all`);
  const label = page.locator(".benchmark-complexity .role-row-header text").first();
  await expect(label).toHaveAttribute("data-highlight-id", /.+/);
  const id = await label.getAttribute("data-highlight-id");
  await page.getByRole("button", { name: "Highlight mode" }).click();
  await label.click();
  await expect(label).toHaveAttribute("aria-pressed", "true");
  expect(query(page).getAll("highlight-benchmark")).toEqual([id]);
  await label.focus();
  await page.keyboard.press("Space");
  await expect(label).toBeFocused();
  await expect(label).toHaveAttribute("aria-pressed", "false");
  expect(query(page).has("highlight-benchmark")).toBe(false);
});

test("Performance retains highlighted runs across cells and drill-down without fetching other cells", async ({ page }) => {
  await page.goto(`${basePath}#/performance?model-set=all`);
  const points = page.locator('.performance-analysis [aria-label^="Run "]');
  await expect(points.last()).toHaveAttribute("data-highlight-id", /.+/);
  const id = (await points.last().getAttribute("data-highlight-id"))!;
  await page.getByRole("button", { name: "Highlight mode" }).click();
  await points.last().focus();
  await page.keyboard.press("Enter");
  await expect(points.last()).toHaveAttribute("aria-pressed", "true");
  const requests: string[] = [];
  page.on("request", (request) => { if (request.url().includes("/data/")) requests.push(request.url()); });
  await page.getByRole("combobox", { name: "Values", exact: true }).selectOption("relative");
  await expect(page.locator(".performance_highlight_halos_marks path")).toHaveCount(1);
  expect(requests).toEqual([]);
  await page.keyboard.press("Escape");
  await points.last().focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#\/run\//);
  await page.getByRole("link", { name: /Back to performance/ }).click();
  await expect(page.locator(".performance_highlight_halos_marks path")).toHaveCount(1);
  const benchmark = page.getByRole("combobox", { name: "Benchmark", exact: true });
  const original = await benchmark.inputValue();
  const alternate = await benchmark.locator("option").evaluateAll((options, current) => options.map((option) => (option as HTMLOptionElement).value).find((value) => value !== current)!, original);
  await benchmark.selectOption(alternate);
  await expect(page.locator(".performance_highlight_halos_marks path")).toHaveCount(0);
  await expect(page.getByRole("status")).toContainText("1 not shown");
  expect(query(page).getAll("highlight-run")).toEqual([id]);
  await benchmark.selectOption(original);
  await expect(page.locator(".performance_highlight_halos_marks path")).toHaveCount(1);
});
