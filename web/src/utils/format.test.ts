import { describe, expect, it } from "vitest";

import {
  formatCount,
  formatMilliseconds,
  formatScore,
  formatSnapshotTimestamp,
  formatUsd,
  formatUsdPerMillion,
  shortHash,
} from "./format";

describe("formatMilliseconds", () => {
  it("uses the runtime locale and common precision for complete millisecond values", () => {
    const value = 1_234_567.8912;
    const expectedNumber = value.toLocaleString(undefined, { maximumFractionDigits: 3 });
    expect(formatMilliseconds(value)).toBe(`${expectedNumber} ms`);
  });

  it("represents unavailable timings without inventing a value", () => {
    expect(formatMilliseconds(null)).toBe("—");
  });

  it("uses shared locale-aware formatting for cost-analysis values", () => {
    expect(formatScore(6.123)).toBe(new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(6.123));
    expect(formatCount(1_234_567)).toBe(new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(1_234_567));
    expect(formatUsd(0.015428)).toBe(new Intl.NumberFormat(undefined, {
      style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 4,
    }).format(0.015428));
    expect(formatUsdPerMillion(0.03)).toContain("/ M tokens");
    expect(formatUsd(null)).toBe("—");
  });
});

describe("provenance formatting", () => {
  it("keeps snapshot timestamps exact and makes their zone explicit", () => {
    expect(formatSnapshotTimestamp("2026-08-22T18:12:20+02:00")).toBe("2026-08-22 18:12:20 UTC+02:00");
    expect(formatSnapshotTimestamp("2026-08-23T00:00:00.123Z")).toBe("2026-08-23 00:00:00 UTC");
    expect(formatSnapshotTimestamp("recorded time unavailable")).toBe("recorded time unavailable");
  });

  it("uses one short-hash representation across provenance links", () => {
    expect(shortHash("ead85ef29d1adf8f46b08805a3c885e4ffc60df3")).toBe("ead85ef29");
  });
});
