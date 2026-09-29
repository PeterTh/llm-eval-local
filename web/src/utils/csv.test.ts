import { describe, expect, it } from "vitest";

import { analyzeCost } from "../analysis/cost";
import { analyzeTime } from "../analysis/time";
import { costDatasetFixture, manifestFixture, runsFixture, timeDatasetFixture } from "../test/fixtures";
import { costSummariesToCsv, runsToCsv, timeSummariesToCsv } from "./csv";
import { parse } from "csv-parse/sync";

describe("runsToCsv", () => {
  it("exports generation statistics in seconds with explicit coverage and empty missing values", () => {
    const dataset = { ...timeDatasetFixture, runs: timeDatasetFixture.runs.map((run) => run.modelId === "unknown-model" ? { ...run, generationTimeSeconds: null } : run) };
    const analysis = analyzeTime(dataset, manifestFixture, { models: [], benchmarks: [], backends: [] });
    analysis.models[0]!.modelLabel = 'Model, "A"';
    const rows = parse(timeSummariesToCsv(analysis.models), { columns: true });
    expect(rows[0]).toMatchObject({ model_label: 'Model, "A"', mean_score: "6", score_run_count: "2", time_run_count: "2", mean_generation_seconds: "120", median_generation_seconds: "120", q1_generation_seconds: "90", q3_generation_seconds: "150" });
    expect(rows[1]).toMatchObject({ time_run_count: "0", unavailable_time_run_count: "1", mean_generation_seconds: "", outlier_count: "" });
  });
  it("includes provenance URLs and quotes special identifiers", () => {
    const csv = runsToCsv(runsFixture.slice(0, 1));
    expect(csv).toContain("timing_fixed,timing_issue_categories,source_url,original_source_url");
    expect(csv).toContain(runsFixture[0]!.sourceUrl);
    expect(csv).toContain("bench&one_model/a?x_gpu+x_r1");
  });

  it("exports timing-fix labels and both source revisions", () => {
    const fixed = runsFixture[1]!;
    const csv = runsToCsv([fixed]);
    expect(csv).toContain("true,missing_rank_aggregation;rank_local_timing");
    expect(csv).toContain(fixed.sourceUrl);
    expect(csv).toContain(fixed.timingCorrection!.originalSource.url);
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
