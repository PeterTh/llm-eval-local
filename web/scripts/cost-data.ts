import type { CostPricingProfile, CostRunRecord } from "../src/data/types";

export type CsvRow = Record<string, string>;

export interface ParsedCostProfiles {
  profiles: CostPricingProfile[];
  pricingAsOf: string;
  selectionPolicy: string;
}

export interface ValidatedCostConfig {
  aliases: Record<string, string>;
  inputTokenAccounting: Record<string, "includes-cached" | "excludes-cached">;
}

function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function required(value: string | undefined, field: string): string {
  invariant(value !== undefined && value.trim() !== "", `missing ${field}`);
  return value;
}

function requiredNumber(value: string | undefined, field: string): number {
  const parsed = Number(required(value, field));
  invariant(Number.isFinite(parsed) && parsed >= 0, `${field} must be a non-negative number`);
  return parsed;
}

function optionalNumber(value: string | undefined, field: string): number | null {
  if (value === undefined || value.trim() === "") return null;
  const parsed = Number(value);
  invariant(Number.isFinite(parsed) && parsed >= 0, `${field} must be a non-negative number`);
  return parsed;
}

function optionalInteger(value: string | undefined, field: string): number | null {
  const parsed = optionalNumber(value, field);
  if (parsed === null) return null;
  const rounded = Math.round(parsed);
  invariant(Math.abs(parsed - rounded) <= 1e-6, `${field} must be an integer`);
  return rounded;
}

function requiredInteger(value: string | undefined, field: string): number {
  const parsed = requiredNumber(value, field);
  invariant(Number.isInteger(parsed), `${field} must be an integer`);
  return parsed;
}

function requiredUrl(value: string | undefined, field: string): string {
  const url = required(value, field);
  try {
    const parsed = new URL(url);
    invariant(parsed.protocol === "https:" || parsed.protocol === "http:", `${field} must use HTTP(S)`);
  } catch {
    throw new Error(`${field} must be an absolute URL`);
  }
  return url;
}

function optionalUrl(value: string | undefined, field: string): string | null {
  if (value === undefined || value.trim() === "") return null;
  return requiredUrl(value, field);
}

function validateDate(value: string, field: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const year = Number(match?.[1]);
  const month = Number(match?.[2]);
  const day = Number(match?.[3]);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  invariant(match !== null && month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth[month - 1]!,
    `${field} must be an ISO date`);
  return value;
}

function mostFrequent(values: readonly string[]): string {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0], "en"))[0]?.[0] ?? "";
}

export function parseCostPricingProfiles(rows: readonly CsvRow[]): ParsedCostProfiles {
  invariant(rows.length > 0, "cost pricing table is empty");
  const identifiers = new Set<string>();
  const profiles = rows.map((row, index): CostPricingProfile => {
    const prefix = `cost pricing row ${index + 1}`;
    const id = required(row.model, `${prefix}.model`);
    invariant(!identifiers.has(id), `duplicate cost pricing profile: ${id}`);
    identifiers.add(id);
    const inputPriceUsdPerMillion = requiredNumber(row.input_price_usd_per_million, `${id}.input_price_usd_per_million`);
    const cachedInputPriceUsdPerMillion = requiredNumber(row.cached_input_price_usd_per_million, `${id}.cached_input_price_usd_per_million`);
    const outputPriceUsdPerMillion = requiredNumber(row.output_price_usd_per_million, `${id}.output_price_usd_per_million`);
    const effectivePriceUsdPerMillion = optionalNumber(row.effective_price_usd_per_million, `${id}.effective_price_usd_per_million`);
    invariant(inputPriceUsdPerMillion > 0 || cachedInputPriceUsdPerMillion > 0 || outputPriceUsdPerMillion > 0,
      `${id} pricing profile has no positive rate`);
    invariant(effectivePriceUsdPerMillion === null || effectivePriceUsdPerMillion > 0,
      `${id}.effective_price_usd_per_million must be positive when present`);
    return {
      id,
      modelLabel: required(row.model_label, `${id}.model_label`),
      inputPriceUsdPerMillion,
      cachedInputPriceUsdPerMillion,
      outputPriceUsdPerMillion,
      effectivePriceUsdPerMillion,
      pricingAsOf: validateDate(required(row.pricing_as_of, `${id}.pricing_as_of`), `${id}.pricing_as_of`),
      pricingModelId: required(row.pricing_model_id, `${id}.pricing_model_id`),
      pricingProvider: required(row.pricing_provider, `${id}.pricing_provider`),
      pricingProviderTag: required(row.pricing_provider_tag, `${id}.pricing_provider_tag`),
      pricingQuantization: required(row.pricing_quantization, `${id}.pricing_quantization`),
      pricingSourceKind: required(row.pricing_source_kind, `${id}.pricing_source_kind`),
      pricingSelectionPolicy: required(row.pricing_selection_policy, `${id}.pricing_selection_policy`),
      pricingCatalogUrl: requiredUrl(row.pricing_catalog_url, `${id}.pricing_catalog_url`),
      pricingEndpointUrl: optionalUrl(row.pricing_endpoint_url, `${id}.pricing_endpoint_url`),
      pricingSourceUrl: requiredUrl(row.pricing_source_url, `${id}.pricing_source_url`),
      secondaryPricingSourceUrl: optionalUrl(row.secondary_pricing_source_url, `${id}.secondary_pricing_source_url`),
      pricingMatchNote: required(row.pricing_match_note, `${id}.pricing_match_note`),
      costMethod: required(row.cost_method, `${id}.cost_method`),
    };
  });
  const pricingDates = new Set(profiles.map((profile) => profile.pricingAsOf));
  invariant(pricingDates.size === 1, `cost pricing table contains inconsistent dates: ${[...pricingDates].join(", ")}`);
  return {
    profiles,
    pricingAsOf: profiles[0]!.pricingAsOf,
    selectionPolicy: mostFrequent(profiles.map((profile) => profile.pricingSelectionPolicy)),
  };
}

export function validateCostConfig(
  value: unknown,
  profiles: readonly CostPricingProfile[],
  modelIds: ReadonlySet<string>,
): ValidatedCostConfig {
  invariant(typeof value === "object" && value !== null && !Array.isArray(value), "cost config must be an object");
  const aliasesValue = (value as { aliases?: unknown }).aliases;
  invariant(typeof aliasesValue === "object" && aliasesValue !== null && !Array.isArray(aliasesValue), "cost aliases must be an object");
  const profileIds = new Set(profiles.map((profile) => profile.id));
  const aliases: Record<string, string> = {};
  for (const [modelId, profileId] of Object.entries(aliasesValue)) {
    invariant(modelId.trim() !== "" && typeof profileId === "string" && profileId.trim() !== "", "cost aliases must map non-empty identifiers");
    invariant(modelIds.has(modelId), `cost alias targets unknown model: ${modelId}`);
    invariant(!profileIds.has(modelId), `cost alias overrides an exact pricing profile: ${modelId}`);
    invariant(profileIds.has(profileId), `cost alias references unknown pricing profile: ${modelId} -> ${profileId}`);
    aliases[modelId] = profileId;
  }
  const accountingValue = (value as { inputTokenAccounting?: unknown }).inputTokenAccounting ?? {};
  invariant(typeof accountingValue === "object" && accountingValue !== null && !Array.isArray(accountingValue), "input token accounting must be an object");
  const inputTokenAccounting: Record<string, "includes-cached" | "excludes-cached"> = {};
  for (const [modelId, convention] of Object.entries(accountingValue)) {
    invariant(modelIds.has(modelId), `input token accounting targets unknown model: ${modelId}`);
    invariant(convention === "includes-cached" || convention === "excludes-cached", `invalid input token accounting convention: ${modelId}`);
    inputTokenAccounting[modelId] = convention;
  }
  return {
    aliases: Object.fromEntries(Object.entries(aliases).sort(([left], [right]) => left.localeCompare(right, "en"))),
    inputTokenAccounting: Object.fromEntries(Object.entries(inputTokenAccounting).sort(([left], [right]) => left.localeCompare(right, "en"))),
  };
}

export function estimateRunCost(
  tokens: Pick<CostRunRecord, "inputTokens" | "cachedInputTokens" | "outputTokens" | "totalTokens">,
  profile: CostPricingProfile,
  inputTokenAccounting: "includes-cached" | "excludes-cached" = "includes-cached",
): number | null {
  if (profile.effectivePriceUsdPerMillion !== null) {
    return tokens.totalTokens === null
      ? null
      : tokens.totalTokens * profile.effectivePriceUsdPerMillion / 1_000_000;
  }
  if (tokens.inputTokens === null || tokens.cachedInputTokens === null || tokens.outputTokens === null) return null;
  const uncachedInputTokens = inputTokenAccounting === "includes-cached"
    ? tokens.inputTokens - tokens.cachedInputTokens
    : tokens.inputTokens;
  invariant(uncachedInputTokens >= 0, "cached tokens exceed an inclusive input-token count");
  return (
    uncachedInputTokens * profile.inputPriceUsdPerMillion
    + tokens.cachedInputTokens * profile.cachedInputPriceUsdPerMillion
    + tokens.outputTokens * profile.outputPriceUsdPerMillion
  ) / 1_000_000;
}

export function costRunFromScoredRow(
  row: CsvRow,
  profiles: ReadonlyMap<string, CostPricingProfile>,
  aliases: Readonly<Record<string, string>>,
  inputTokenAccounting: Readonly<Record<string, "includes-cached" | "excludes-cached">>,
  scoreMinimum: number,
  scoreMaximum: number,
): CostRunRecord {
  const modelId = required(row.model, "cost run model");
  const benchmarkId = required(row.benchmark, `${modelId}.benchmark`);
  const backendId = required(row.par_type, `${modelId}.par_type`);
  const repetition = requiredInteger(row.run, `${modelId}/${benchmarkId}/${backendId}.run`);
  invariant(repetition > 0, `${modelId}/${benchmarkId}/${backendId}.run must be positive`);
  const overallScore = requiredInteger(row.overall_score, `${modelId}/${benchmarkId}/${backendId}/r${repetition}.overall_score`);
  invariant(overallScore >= scoreMinimum && overallScore <= scoreMaximum, `${modelId}/${benchmarkId}/${backendId}/r${repetition}.overall_score is out of bounds`);
  const id = `${benchmarkId}_${modelId}_${backendId}_r${repetition}`;
  const inputTokens = optionalInteger(row.input_tokens, `${id}.input_tokens`);
  const cachedInputTokens = optionalInteger(row.cached_tokens, `${id}.cached_tokens`);
  const outputTokens = optionalInteger(row.output_tokens, `${id}.output_tokens`);
  const suppliedTotalTokens = optionalInteger(row.total_tokens, `${id}.total_tokens`);
  const splitPresent = [inputTokens, cachedInputTokens, outputTokens].filter((value) => value !== null).length;
  invariant(splitPresent === 0 || splitPresent === 3, `${id} has a partial token split`);
  const accountingConvention = inputTokenAccounting[modelId] ?? "includes-cached";
  invariant(accountingConvention === "excludes-cached" || inputTokens === null || cachedInputTokens! <= inputTokens,
    `${id} cached tokens exceed an inclusive input-token count`);
  if (inputTokens !== null && suppliedTotalTokens !== null) {
    invariant(suppliedTotalTokens === inputTokens + outputTokens!, `${id} total tokens disagree with input plus output`);
  }
  const totalTokens = suppliedTotalTokens ?? (inputTokens === null ? null : inputTokens + outputTokens!);
  const pricingProfileId = profiles.has(modelId) ? modelId : aliases[modelId] ?? null;
  const profile = pricingProfileId === null ? null : profiles.get(pricingProfileId) ?? null;
  invariant(pricingProfileId === null || profile !== null, `${id} references missing profile ${pricingProfileId}`);
  const tokenRecord = { inputTokens, cachedInputTokens, outputTokens, totalTokens };
  const estimatedCostUsd = profile ? estimateRunCost(tokenRecord, profile, accountingConvention) : null;
  invariant(estimatedCostUsd === null || Number.isFinite(estimatedCostUsd), `${id} produced a malformed cost`);
  return {
    id,
    modelId,
    benchmarkId,
    backendId,
    repetition,
    overallScore,
    pricingProfileId,
    ...tokenRecord,
    estimatedCostUsd,
  };
}

function mean(values: readonly number[]): number | null {
  return values.length === 0 ? null : values.reduce((total, value) => total + value, 0) / values.length;
}

function close(actual: number | null, expected: number | null, field: string): void {
  if (actual === null || expected === null) {
    invariant(actual === expected, `${field} differs: ${String(actual)} != ${String(expected)}`);
    return;
  }
  const tolerance = Math.max(1.1e-6, Math.abs(expected) * 1e-12);
  invariant(Math.abs(actual - expected) <= tolerance, `${field} differs: ${actual} != ${expected}`);
}

export function reconcileCanonicalCostAggregates(
  costRuns: readonly CostRunRecord[],
  canonicalRows: readonly CsvRow[],
): void {
  for (const row of canonicalRows) {
    const modelId = required(row.model, "canonical cost model");
    const modelRuns = costRuns.filter((run) => run.modelId === modelId);
    invariant(modelRuns.length > 0, `canonical cost model has no scored runs: ${modelId}`);
    const costRunsForModel = modelRuns.filter((run): run is CostRunRecord & { estimatedCostUsd: number } => run.estimatedCostUsd !== null);
    invariant(modelRuns.length === requiredInteger(row.score_run_count, `${modelId}.score_run_count`), `${modelId}.score_run_count differs`);
    invariant(costRunsForModel.length === requiredInteger(row.cost_run_count, `${modelId}.cost_run_count`), `${modelId}.cost_run_count differs`);
    close(mean(modelRuns.map((run) => run.overallScore)), optionalNumber(row.mean_overall_score, `${modelId}.mean_overall_score`), `${modelId}.mean_overall_score`);
    close(mean(costRunsForModel.flatMap((run) => run.totalTokens === null ? [] : [run.totalTokens])), optionalNumber(row.mean_total_tokens, `${modelId}.mean_total_tokens`), `${modelId}.mean_total_tokens`);
    close(mean(costRunsForModel.flatMap((run) => run.inputTokens === null ? [] : [run.inputTokens])), optionalNumber(row.mean_input_tokens, `${modelId}.mean_input_tokens`), `${modelId}.mean_input_tokens`);
    close(mean(costRunsForModel.flatMap((run) => run.cachedInputTokens === null ? [] : [run.cachedInputTokens])), optionalNumber(row.mean_cached_input_tokens, `${modelId}.mean_cached_input_tokens`), `${modelId}.mean_cached_input_tokens`);
    close(mean(costRunsForModel.flatMap((run) => run.outputTokens === null ? [] : [run.outputTokens])), optionalNumber(row.mean_output_tokens, `${modelId}.mean_output_tokens`), `${modelId}.mean_output_tokens`);
    close(mean(costRunsForModel.map((run) => run.estimatedCostUsd)), optionalNumber(row.estimated_cost_usd_per_run, `${modelId}.estimated_cost_usd_per_run`), `${modelId}.estimated_cost_usd_per_run`);
  }
}
