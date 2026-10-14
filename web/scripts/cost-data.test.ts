import { describe, expect, it } from "vitest";

import type { CostPricingProfile, CostRunRecord } from "../src/data/types";
import {
  costRunFromScoredRow,
  estimateRunCost,
  estimateContextRunCost,
  parseContextUsageRecords,
  parseCostPricingProfiles,
  reconcileCanonicalCostAggregates,
  validateCostConfig,
  type CsvRow,
} from "./cost-data";

function pricingRow(overrides: Partial<CsvRow> = {}): CsvRow {
  return {
    model: "model-a",
    model_label: "Model A",
    score_run_count: "1",
    cost_run_count: "1",
    mean_overall_score: "7.000000",
    mean_total_tokens: "120.000000",
    mean_input_tokens: "100.000000",
    mean_cached_input_tokens: "80.000000",
    mean_output_tokens: "20.000000",
    input_price_usd_per_million: "1.000000",
    cached_input_price_usd_per_million: "0.100000",
    output_price_usd_per_million: "4.000000",
    effective_price_usd_per_million: "",
    estimated_cost_usd_per_run: "0.000108",
    pricing_as_of: "2026-08-22",
    pricing_model_id: "provider/model-a",
    pricing_provider: "Provider",
    pricing_provider_tag: "provider/fp8",
    pricing_quantization: "fp8",
    pricing_source_kind: "Test source",
    pricing_selection_policy: "Test selection policy",
    pricing_catalog_url: "https://example.test/catalog",
    pricing_endpoint_url: "https://example.test/endpoint",
    pricing_source_url: "https://example.test/model-a",
    secondary_pricing_source_url: "",
    pricing_match_note: "exact model",
    cost_method: "split token pricing",
    ...overrides,
  };
}

function splitProfile(): CostPricingProfile {
  return parseCostPricingProfiles([pricingRow()]).profiles[0]!;
}

function contextFixture() {
  const id = "bench_model-a_cpu_r1";
  const profile = parseCostPricingProfiles([pricingRow({
    input_price_usd_per_million: "0.1", cached_input_price_usd_per_million: "0.01", output_price_usd_per_million: "0.5",
    request_input_threshold_tokens: "100000", long_input_price_usd_per_million: "0.5",
    long_cached_input_price_usd_per_million: "0.05", long_output_price_usd_per_million: "2.5",
    context_usage_path: "batches/test/usage.jsonl", context_source_commit: "a".repeat(40),
  })]).profiles[0]!;
  const evidence = {
    schema_version: 1, id, source_commit: "a".repeat(40), pricing_as_of: "2026-08-22",
    request_input_threshold_tokens: 100000, requests: 2, per_request_output_available: false,
    output_band_evidence: "derived_from_reported_list_cost_and_native_output_total",
    comparison_cost_nanodollars: 11485500, cache_write_surcharge_nanodollars: 102500, native_list_cost_nanodollars: 11588000,
    bands: {
      short: { input_tokens: 9900, cache_read_input_tokens: 90000, cache_creation_5m_tokens: 100, cache_creation_1h_tokens: 0,
        output_tokens: 20, inclusive_input_tokens: 100000, requests: 1, max_request_input_tokens: 100000, streamed_output_lower_bound: 1 },
      long: { input_tokens: 9801, cache_read_input_tokens: 90000, cache_creation_5m_tokens: 0, cache_creation_1h_tokens: 200,
        output_tokens: 30, inclusive_input_tokens: 100001, requests: 1, max_request_input_tokens: 100001, streamed_output_lower_bound: 1 },
    },
  };
  const parsed = parseContextUsageRecords(JSON.stringify(evidence)).get(id)!;
  const tokens = { inputTokens: 200001, cachedInputTokens: 180000, outputTokens: 50, totalTokens: 200051 };
  return { id, profile, evidence: parsed, tokens };
}

describe("cost data generation", () => {
  it("prices context bands separately and never silently falls back to flat rates", () => {
    const { id, profile, evidence, tokens } = contextFixture();
    expect(estimateContextRunCost(tokens, profile, evidence)).toBe(0.0114855);
    expect(() => estimateRunCost(tokens, profile)).toThrow(/requires band evidence/);
    const row = { model: "model-a", benchmark: "bench", par_type: "cpu", run: "1", overall_score: "8",
      input_tokens: "200001", cached_tokens: "180000", output_tokens: "50", total_tokens: "200051" };
    expect(() => costRunFromScoredRow(row, new Map([[profile.id, profile]]), {}, {}, 0, 10)).toThrow(/missing request-context/);
    expect(costRunFromScoredRow(row, new Map([[profile.id, profile]]), {}, {}, 0, 10, new Map([[id, evidence]])).estimatedCostUsd).toBe(0.0114855);
  });

  it("checks context threshold, totals, provenance and duplicate evidence", () => {
    const { profile, evidence, tokens } = contextFixture();
    const incorrect = structuredClone(evidence);
    incorrect.bands.long.max_request_input_tokens = 100000;
    expect(() => estimateContextRunCost(tokens, profile, incorrect)).toThrow(/wrong context band/);
    expect(() => estimateContextRunCost({ ...tokens, cachedInputTokens: 170000 }, profile, evidence)).toThrow(/scored tokens/);
    expect(() => estimateContextRunCost(tokens, profile, { ...evidence, source_commit: "b".repeat(40) })).toThrow(/revision/);
    expect(() => estimateContextRunCost(tokens, profile, { ...evidence, comparison_cost_nanodollars: 1 })).toThrow(/cost mismatch/);
    expect(() => parseContextUsageRecords(`${JSON.stringify(evidence)}\n${JSON.stringify(evidence)}`)).toThrow(/duplicate/);
  });

  it("keeps historical prices dated independently when a later batch is added", () => {
    const parsed = parseCostPricingProfiles([pricingRow(), pricingRow({ model: "model-b", pricing_as_of: "2026-09-29" })]);
    expect(parsed.pricingAsOf).toBe("2026-09-29");
    expect(parsed.profiles.map((profile) => profile.pricingAsOf)).toEqual(["2026-08-22", "2026-09-29"]);
  });
  it("prices inclusive and exclusive cache accounting and the combined-token proxy", () => {
    const profile = splitProfile();
    const tokens = { inputTokens: 100, cachedInputTokens: 80, outputTokens: 20, totalTokens: 120 };
    expect(estimateRunCost(tokens, profile, "includes-cached")).toBeCloseTo(0.000108, 12);
    expect(estimateRunCost(tokens, profile, "excludes-cached")).toBeCloseTo(0.000188, 12);
    expect(estimateRunCost({ ...tokens, inputTokens: null }, profile)).toBeNull();
    expect(estimateRunCost(tokens, { ...profile, effectivePriceUsdPerMillion: 3.5 })).toBeCloseTo(0.00042, 12);
  });

  it("validates unique dated profiles, URLs, aliases, and accounting conventions", () => {
    const profiles = parseCostPricingProfiles([pricingRow()]);
    expect(profiles).toMatchObject({ pricingAsOf: "2026-08-22", selectionPolicy: "Test selection policy" });
    expect(validateCostConfig({
      aliases: { alias: "model-a" },
      inputTokenAccounting: { alias: "excludes-cached" },
    }, profiles.profiles, new Set(["model-a", "alias"]))).toEqual({
      aliases: { alias: "model-a" },
      inputTokenAccounting: { alias: "excludes-cached" },
    });
    expect(() => parseCostPricingProfiles([pricingRow(), pricingRow()])).toThrow(/duplicate/);
    expect(() => parseCostPricingProfiles([pricingRow({ pricing_source_url: "relative" })])).toThrow(/URL/);
    expect(() => parseCostPricingProfiles([pricingRow({ pricing_as_of: "2026-02-31" })])).toThrow(/ISO date/);
    expect(() => parseCostPricingProfiles([pricingRow({ long_input_price_usd_per_million: "0.5" })])).toThrow(/threshold/);
    expect(() => validateCostConfig({ aliases: { alias: "missing" } }, profiles.profiles, new Set(["alias"]))).toThrow(/unknown pricing profile/);
  });

  it("normalizes harmless floating token serialization and preserves missing costs", () => {
    const profile = splitProfile();
    const profiles = new Map([[profile.id, profile]]);
    const run = costRunFromScoredRow({
      model: "model-a", benchmark: "bench", par_type: "cpu", run: "1", overall_score: "7",
      input_tokens: "99.99999999999999", cached_tokens: "80.0", output_tokens: "20.0", total_tokens: "120.0",
    }, profiles, {}, {}, 0, 10);
    expect(run).toMatchObject({ inputTokens: 100, totalTokens: 120, estimatedCostUsd: 0.000108 });

    const missing = costRunFromScoredRow({
      model: "model-a", benchmark: "bench", par_type: "cpu", run: "2", overall_score: "5",
      input_tokens: "", cached_tokens: "", output_tokens: "", total_tokens: "",
    }, profiles, {}, {}, 0, 10);
    expect(missing.estimatedCostUsd).toBeNull();
  });

  it("reconciles generated full-data means against the rounded canonical table", () => {
    const run: CostRunRecord = {
      id: "bench_model-a_cpu_r1", modelId: "model-a", benchmarkId: "bench", backendId: "cpu", repetition: 1,
      overallScore: 7, pricingProfileId: "model-a", inputTokens: 100, cachedInputTokens: 80,
      outputTokens: 20, totalTokens: 120, estimatedCostUsd: 0.0001080000001,
    };
    expect(() => reconcileCanonicalCostAggregates([run], [pricingRow()])).not.toThrow();
    expect(() => reconcileCanonicalCostAggregates([run], [pricingRow({ estimated_cost_usd_per_run: "0.100000" })])).toThrow(/estimated_cost/);
  });
});
