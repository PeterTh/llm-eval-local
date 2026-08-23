import { describe, expect, it } from "vitest";

import { formatMilliseconds } from "./format";

describe("formatMilliseconds", () => {
  it("uses the runtime locale and common precision for complete millisecond values", () => {
    const value = 1_234_567.8912;
    const expectedNumber = value.toLocaleString(undefined, { maximumFractionDigits: 3 });
    expect(formatMilliseconds(value)).toBe(`${expectedNumber} ms`);
  });

  it("represents unavailable timings without inventing a value", () => {
    expect(formatMilliseconds(null)).toBe("—");
  });
});
