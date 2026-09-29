import { describe, expect, it } from "vitest";
import { parseGenerationTime } from "./time-data";

describe("generation duration parsing", () => {
  it("preserves seconds and recorded retry-adjusted precision", () => {
    expect(parseGenerationTime("3265.461", "run")).toBe(3265.461);
    expect(parseGenerationTime(" 1.2e2 ", "run")).toBe(120);
  });
  it.each([undefined, "", "  "])("keeps a missing duration unavailable: %s", (value) => {
    expect(parseGenerationTime(value, "run")).toBeNull();
  });
  it.each(["0", "-1", "NaN", "Infinity", "1e999", "abc", "60 seconds", "0x10"])("rejects an invalid duration: %s", (value) => {
    expect(() => parseGenerationTime(value, "example-run")).toThrow(/example-run.total_time/);
  });
});
