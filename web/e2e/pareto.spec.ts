import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";

for (const kind of ["cost", "time"] as const) {
  test(`${kind} Pareto indicators agree across charts, tables, scales and themes`, async ({ page }, testInfo) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    let frontierIds: string[] | undefined;
    for (const colorScheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme });
      for (const scale of ["linear", "log"]) {
        await page.goto(`${basePath}#/${kind}?model-set=all&scale=${scale}`);
        const chart = page.locator(`.${kind}-analysis`);
        const points = page.locator(`.${kind}_points path`);
        await expect(points).toHaveCount(27);
        await page.evaluate(async () => { await document.fonts.ready; });
        const values = await points.evaluateAll((elements, route) => elements.map((element) => {
          const item = (element as SVGElement & { __data__: { x: number; y: number; datum: {
            modelId: string; modelLabel: string; meanEstimatedCostUsd: number; minutes: number; meanScore: number;
          } } }).__data__;
          return {
            id: item.datum.modelId, label: item.datum.modelLabel,
            value: route === "cost" ? item.datum.meanEstimatedCostUsd : item.datum.minutes,
            score: item.datum.meanScore, x: item.x, y: item.y,
            description: element.getAttribute("aria-label"), strokeWidth: Number(element.getAttribute("stroke-width")),
          };
        }), kind);
        const front = values.filter((point) => !values.some((other) => other.value <= point.value && other.score >= point.score
          && (other.value < point.value || other.score > point.score))).sort((a, b) => a.value - b.value);
        const expectedIds = front.map((point) => point.id).sort();
        frontierIds ??= expectedIds;
        expect(expectedIds).toEqual(frontierIds);
        for (const point of values) {
          const onFront = expectedIds.includes(point.id);
          expect(point.description).toContain(`Pareto front: ${onFront ? "Yes" : "No"}`);
          expect(point.strokeWidth).toBe(onFront ? 2.5 : 1.3);
        }

        const line = chart.locator(`.${kind}_pareto_line path`);
        await expect(line).toHaveAttribute("stroke-dasharray", "6,4");
        const coordinates = [...(await line.getAttribute("d"))!.matchAll(/[ML](-?[\d.e+-]+),(-?[\d.e+-]+)/gi)]
          .map((match) => [Number(match[1]), Number(match[2])]);
        expect(coordinates).toHaveLength(front.length);
        coordinates.forEach(([x, y], index) => {
          expect(x).toBeCloseTo(front[index]!.x, 2);
          expect(y).toBeCloseTo(front[index]!.y, 2);
        });
        await expect(line).not.toHaveAttribute("tabindex");
        await expect(chart.getByText("Pareto front · current selection", { exact: true })).toBeVisible();
        const labelLayout = await chart.locator(`.${kind}_labels text`).evaluateAll((elements) => {
          const visible = elements.filter((element) => getComputedStyle(element).opacity !== "0");
          const boxes = visible.map((element) => element.getBoundingClientRect());
          const overlaps: string[] = [];
          for (let a = 0; a < boxes.length; a++) for (let b = a + 1; b < boxes.length; b++) {
            if (Math.min(boxes[a].right, boxes[b].right) - Math.max(boxes[a].left, boxes[b].left) > 2
              && Math.min(boxes[a].bottom, boxes[b].bottom) - Math.max(boxes[a].top, boxes[b].top) > 2) {
              overlaps.push(`${visible[a].textContent} / ${visible[b].textContent}`);
            }
          }
          return { visible: visible.length, overlaps, hidden: elements.filter((element) => getComputedStyle(element).opacity === "0").map((element) => element.textContent) };
        });
        expect(labelLayout).toEqual({ visible: 27, overlaps: [], hidden: [] });
        await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
        await page.screenshot({ path: testInfo.outputPath(`${kind}-pareto-${colorScheme}-${scale}.png`), fullPage: true, clip: (await chart.boundingBox())! });

        await page.locator(`.${kind}-data summary`).click();
        const tableStatuses = await page.locator(`.${kind}-data table`).evaluate((table) => {
          const index = [...table.querySelectorAll("thead th")].findIndex((header) => header.textContent === "Pareto front");
          return [...table.querySelectorAll("tbody tr")].map((row) => ({
            label: row.children[0]!.textContent, status: row.children[index]!.textContent,
          }));
        });
        expect(tableStatuses).toHaveLength(values.length);
        for (const row of tableStatuses) {
          expect(row.status).toBe(front.some((point) => point.label === row.label) ? "Yes" : "No");
        }
        await page.locator(`.${kind}-data summary`).click();
        for (const onFront of [true, false]) {
          // Nearly coincident model markers can share a hit target at linear scale.
          // Check a well-separated point from each class and verify its identity too.
          const target = values.filter((value) => expectedIds.includes(value.id) === onFront)
            .map((value) => ({ value, gap: Math.min(...values.filter((other) => other.id !== value.id)
              .map((other) => Math.hypot(value.x - other.x, value.y - other.y))) }))
            .sort((a, b) => b.gap - a.gap)[0]!.value;
          const point = points.nth(values.findIndex((value) => value.id === target.id));
          await point.hover({ force: true });
          await expect(page.locator("#vg-tooltip-element")).toContainText(target.label);
          const tooltipRow = page.locator("#vg-tooltip-element tr").filter({ hasText: "Pareto front" });
          await expect(tooltipRow).toContainText(onFront ? "Yes" : "No");
          await page.mouse.move(1, 1);
        }
      }
    }

    await page.locator(`.${kind}-analysis`).getByLabel("Export chart").click();
    const saveSvg = page.getByRole("link", { name: "Save as SVG" });
    // Vega prepares the download URL asynchronously on mousedown.
    await saveSvg.dispatchEvent("mousedown", { button: 0 });
    await expect(saveSvg).toHaveAttribute("href", /^blob:/);
    const downloadPromise = page.waitForEvent("download");
    await saveSvg.click();
    const exported = await readFile((await (await downloadPromise).path())!, "utf8");
    expect(exported).toContain(`${kind}_pareto_line`);
    expect(exported).toContain('stroke-dasharray="6,4"');
    expect(errors).toEqual([]);
  });

  test(`${kind} promotes filtered models and handles singleton and coincident fronts`, async ({ page }) => {
    await page.goto(`${basePath}#/${kind}?model-set=all`);
    const points = page.locator(`.${kind}_points path`);
    await expect(points).toHaveCount(27);
    const hiddenFront = await points.evaluateAll((elements) => elements.map((element) => {
      const datum = (element as SVGElement & { __data__: { datum: { modelId: string; isPareto: boolean } } }).__data__.datum;
      return { id: datum.modelId, isPareto: datum.isPareto };
    }));
    const dominated = hiddenFront.find((point) => !point.isPareto)!.id;
    const second = hiddenFront.find((point) => point.id !== dominated)!.id;
    await page.goto(`${basePath}#/${kind}?model=${encodeURIComponent(dominated)}`);
    await expect(points).toHaveCount(1);
    await expect(points.first()).toHaveAttribute("aria-label", /Pareto front: Yes$/);
    await expect(points.first()).toHaveAttribute("stroke-width", "2.5");
    expect(await page.locator(`.${kind}_pareto_line path`).getAttribute("d")).toBeFalsy();
    await points.first().focus();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/#\/runs\?model=/);

    // Keep real IDs and schema/provenance while making two models' plotted aggregates identical.
    await page.route(new RegExp(`/data/${kind}\\.[^/]+\\.json$`), async (route) => {
      const response = await route.fetch();
      const dataset = await response.json();
      for (const run of dataset.runs) {
        run.overallScore = 8;
        if (kind === "cost") run.estimatedCostUsd = 1;
        else run.generationTimeSeconds = 60;
      }
      await route.fulfill({ response, json: dataset });
    });
    await page.goto(`${basePath}#/${kind}?model=${encodeURIComponent(dominated)}&model=${encodeURIComponent(second)}`);
    await page.reload();
    await expect(points).toHaveCount(2);
    for (const point of await points.all()) {
      await expect(point).toHaveAttribute("aria-label", /Pareto front: Yes$/);
      await expect(point).toHaveAttribute("stroke-width", "2.5");
    }
    expect(await page.locator(`.${kind}_pareto_line path`).getAttribute("d")).toBeFalsy();
  });
}
