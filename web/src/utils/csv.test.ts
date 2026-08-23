import { describe, expect, it } from "vitest";

import { runsFixture } from "../test/fixtures";
import { runsToCsv } from "./csv";

describe("runsToCsv", () => {
  it("includes provenance URLs and quotes special identifiers", () => {
    const csv = runsToCsv(runsFixture.slice(0, 1));
    expect(csv).toContain("source_url,validation_evidence_url,benchmark_evidence_url");
    expect(csv).toContain(runsFixture[0]!.sourceUrl);
    expect(csv).toContain("bench&one_model/a?x_gpu+x_r1");
  });
});
