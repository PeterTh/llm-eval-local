import { describe, expect, it } from "vitest";

import { analyzeCost } from "../analysis/cost";
import { costDatasetFixture, manifestFixture, runsFixture } from "../test/fixtures";
import { costSummariesToCsv, runsToCsv } from "./csv";

describe("runsToCsv", () => {
  it("includes provenance URLs and quotes special identifiers", () => {
    const csv = runsToCsv(runsFixture.slice(0, 1));
    expect(csv).toContain("source_url,validation_evidence_url,benchmark_evidence_url");
    expect(csv).toContain(runsFixture[0]!.sourceUrl);
    expect(csv).toContain("bench&one_model/a?x_gpu+x_r1");
  });

  it("exports displayed cost aggregates with rates and pricing provenance", () => {
    const analysis = analyzeCost(costDatasetFixture, manifestFixture, {
      models: ["model/a?x"], benchmarks: [], backends: [],
    });
    const csv = costSummariesToCsv(analysis.models);
    expect(csv).toContain("estimated_mean_cost_usd");
    expect(csv).toContain("pricing_endpoint_url");
    expect(csv).toContain("model/a?x");
    expect(csv).toContain("https://example.test/models/unknown-model");
    expect(csv).toContain("Input less cached input");
  });
});
