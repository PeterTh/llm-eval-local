import { expect, test } from "@playwright/test";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? "/" + repositoryName + "/" : "/";

for (const route of ["cost", "time"]) {
  for (const scale of ["log", "linear"]) {
    test("all-model " + route + " chart stays stable on hover and resizes at " + scale + " scale", async ({ page }, testInfo) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(basePath + "#/" + route + "?model-set=all&scale=" + scale);
      const points = page.locator("." + route + "_points path");
      await expect(points).toHaveCount(30);
      const selectedIds = await points.evaluateAll((elements) => {
        const data = elements.map((element) => (element as SVGElement & { __data__: { datum: { modelId: string; isPareto: boolean } } }).__data__.datum);
        return [data.find((point) => point.isPareto)!.modelId, data.find((point) => !point.isPareto)!.modelId];
      });
      const highlighted = new URLSearchParams({ "model-set": "all", scale });
      selectedIds.forEach((id) => highlighted.append("highlight-model", id));
      await page.goto(`${basePath}#/${route}?${highlighted}`);
      await expect(page.locator(`.${route}_highlight_halos path`)).toHaveCount(2);
      await page.evaluate(async () => { await document.fonts.ready; });
      const chart = page.locator("." + route + "-analysis .chart");
      const snapshot = () => chart.evaluate((element) => {
        const svg = element.querySelector("svg.marks")!;
        return {
          width: element.clientWidth,
          height: element.clientHeight,
          svg: [svg.getAttribute("width"), svg.getAttribute("height")],
          geometry: [...svg.querySelectorAll("g, path, text, line")].map((mark) =>
            ["transform", "x", "y", "x2", "y2", "d", "opacity", "text-anchor"].map((attribute) => mark.getAttribute(attribute))),
        };
      });
      const widths = testInfo.project.name === "mobile" ? [390, 320] : [1440, 1920, 1100];
      for (const width of widths) {
        await page.setViewportSize({ width, height: testInfo.project.name === "mobile" ? 844 : 1100 });
        // Wait for the real container resize and its layout, without using a hover to settle it.
        await expect.poll(() => chart.evaluate((element) => Number(element.querySelector("svg.marks")?.getAttribute("width"))
          === Math.max(280, element.clientWidth - 32))).toBe(true);
        await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
        const baseline = await snapshot();
        for (const point of await points.all()) {
          await point.hover({ force: true });
          expect(await snapshot(), "Geometry changed on hover at viewport width " + width).toEqual(baseline);
          await page.mouse.move(1, 1);
          expect(await snapshot(), "Geometry changed on pointer exit at viewport width " + width).toEqual(baseline);
        }
        if (width === 1920 || width === 390) {
          await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
          await page.mouse.move(width - 4, 4);
          await page.screenshot({ path: testInfo.outputPath(route + "-" + scale + ".png"), fullPage: true });
        }
      }
      expect(errors).toEqual([]);
    });
  }
}
