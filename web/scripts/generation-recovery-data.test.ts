import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { generationRecoveryPath, parseGenerationRecovery } from "./generation-recovery-data";

const id = "qtclustering_claude-sonnet-5.5-cc-medium_omp_r2";
const receipt = {
  schema_version: 1, run_id: id, campaign_id: "20261014-212207", approved_by: "user",
  decision: "retain_completed_native_result", generation_time_source: "claude_result_duration_ms",
  generation_time_recovered: true, wrapper_exit_status_available: false,
  wrapper_wall_time_seconds: null, wrapper_start_time: null, wrapper_end_time: null, duration_ms: 865229,
};
function fixture(extra: Record<string, unknown> = {}) {
  const bytes = JSON.stringify({ ...receipt, ...extra });
  return { bytes, row: {
    source_batch: receipt.campaign_id, total_time: "865.229", generation_time_recovered: "true",
    generation_time_source: "claude_result_duration_ms", wrapper_exit_status_available: "false",
    generation_recovery_sha256: createHash("sha256").update(bytes).digest("hex"),
  } };
}
const url = "https://github.com/example/evidence/blob/pinned/recovery.json";

describe("generation recovery provenance", () => {
  it("leaves historical and ordinary durations unflagged", () => {
    expect(generationRecoveryPath({}, "historical")).toBeNull();
    expect(generationRecoveryPath({ generation_time_recovered: "false" }, "normal")).toBeNull();
  });
  it("binds the approved native duration and explicitly unknown wrapper status", () => {
    const { row, bytes } = fixture();
    expect(generationRecoveryPath(row, id)).toBe(`batches/${receipt.campaign_id}/generation/recoveries/${id}.json`);
    expect(parseGenerationRecovery(row, id, bytes, url)).toEqual({
      source: "claude_result_duration_ms", wrapperExitStatusAvailable: false,
      evidenceSha256: row.generation_recovery_sha256, evidenceUrl: url,
    });
  });
  it("fails closed on missing, altered, or unflagged provenance", () => {
    const { row, bytes } = fixture();
    expect(() => generationRecoveryPath({ ...row, generation_time_recovered: "false" }, id)).toThrow(/Unflagged/);
    expect(() => generationRecoveryPath({ ...row, source_batch: "../escape" }, id)).toThrow(/Unsafe/);
    expect(() => generationRecoveryPath({ ...row, generation_time_recovered: "yes" }, id)).toThrow(/flag/);
    expect(() => parseGenerationRecovery(row, id, bytes + " ", url)).toThrow(/provenance/);
    for (const change of [{ total_time: "865" }, { total_time: "" }, { generation_recovery_sha256: "" },
      { generation_time_source: "wrapper" }, { wrapper_exit_status_available: "true" }]) {
      expect(() => parseGenerationRecovery({ ...row, ...change }, id, bytes, url)).toThrow();
    }
  });
  it.each([
    { run_id: "another" }, { campaign_id: "20260101-000000" }, { approved_by: "unknown" },
    { duration_ms: 865230 }, { duration_ms: 865229.5 }, { generation_time_recovered: false },
    { wrapper_wall_time_seconds: 865.229 }, { wrapper_start_time: "invented" },
    { wrapper_end_time: "invented" }, { wrapper_exit_status_available: true },
  ])("rejects inconsistent receipt fields: %j", (change) => {
    const { row, bytes } = fixture(change);
    expect(() => parseGenerationRecovery(row, id, bytes, url)).toThrow(/receipt/);
  });
});
