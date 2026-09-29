import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { manifestFixture, timeDatasetFixture } from "../test/fixtures";
import { clearDataCacheForTests, loadTimeDataset } from "./client";
import { timeDatasetSchema } from "./schema";

beforeEach(clearDataCacheForTests);
afterEach(() => vi.unstubAllGlobals());
const response = (value: unknown) => new Response(JSON.stringify(value));

describe("time dataset validation and loading", () => {
  it("validates durations and duplicate identities while preserving unavailable values", () => {
    expect(timeDatasetSchema.parse(timeDatasetFixture)).toEqual(timeDatasetFixture);
    for (const duration of [0, -1, Infinity, NaN, undefined]) {
      expect(() => timeDatasetSchema.parse({ ...timeDatasetFixture, runs: [{ ...timeDatasetFixture.runs[0], generationTimeSeconds: duration }] })).toThrow();
    }
    expect(timeDatasetSchema.parse({ ...timeDatasetFixture, runs: [{ ...timeDatasetFixture.runs[0], generationTimeSeconds: null }] }).runs[0]?.generationTimeSeconds).toBeNull();
    expect(() => timeDatasetSchema.parse({ ...timeDatasetFixture, runs: [timeDatasetFixture.runs[0], timeDatasetFixture.runs[0]] })).toThrow(/duplicate time run/);
  });
  it("shares requests and checks the scoring digest even for cached data", async () => {
    const fetch = vi.fn(async () => response(timeDatasetFixture));
    vi.stubGlobal("fetch", fetch);
    const loaded = await Promise.all([loadTimeDataset(manifestFixture), loadTimeDataset(manifestFixture)]);
    expect(loaded).toEqual([timeDatasetFixture, timeDatasetFixture]);
    expect(fetch).toHaveBeenCalledTimes(1);
    await expect(loadTimeDataset({ ...manifestFixture, scoringDigest: "a".repeat(64) })).rejects.toThrow(/source digest/);
  });
  it("allows retry after a network or validation failure", async () => {
    const fetch = vi.fn()
      .mockResolvedValueOnce(new Response("unavailable", { status: 503 }))
      .mockResolvedValueOnce(response({ ...timeDatasetFixture, sourceDigest: "a".repeat(64) }))
      .mockResolvedValueOnce(response(timeDatasetFixture));
    vi.stubGlobal("fetch", fetch);
    await expect(loadTimeDataset(manifestFixture)).rejects.toThrow(/503/);
    await expect(loadTimeDataset(manifestFixture)).rejects.toThrow(/source digest/);
    await expect(loadTimeDataset(manifestFixture)).resolves.toEqual(timeDatasetFixture);
    expect(fetch).toHaveBeenCalledTimes(3);
  });
});
