import { describe, expect, it } from "vitest";

import type { CostPricingProfile, CostRunRecord } from "../src/data/types";
import {
  costRunFromScoredRow,
  estimateRunCost,
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

describe("cost data generation", () => {
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
