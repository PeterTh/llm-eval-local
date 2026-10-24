import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { generationTerminationPath, parseGenerationTermination } from "./generation-termination-data";

const id = "qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r5";
const batch = "20261019-134042";
const receipt = { schema_version: 1, run_id: id, session_id: "session", approved_by: "user",
  decision: "retain_original_without_restart", reason: "model_caused_termination", usage_complete: false,
  native_process_receipt_available: false };
const counts = { input_tokens: 100, cached_input_tokens: 80, cache_write_input_tokens: 0,
  output_tokens: 10, reasoning_output_tokens: 7, total_tokens: 110 };
function fixture(extra: Record<string, unknown> = {}) {
  const bytes = JSON.stringify({ ...receipt, ...extra });
  return { bytes, row: { source_batch: batch, token_usage_complete: "false", generation_outcome: "generation_model_terminated",
    generation_failure_reason: "model_caused_termination", token_usage_session_id: "session", token_usage_source: "opencode_native_step_finish",
    partial_token_counts: JSON.stringify(counts), termination_record_sha256: createHash("sha256").update(bytes).digest("hex") } };
}
const url = "https://example.test/termination.json";

describe("generation termination evidence", () => {
  it("does not reinterpret legacy or complete usage", () => {
    expect(generationTerminationPath({}, "legacy")).toBeNull();
    expect(generationTerminationPath({ token_usage_complete: "true", generation_outcome: "completed" }, "complete")).toBeNull();
  });
  it("retains a lower bound and the approved original-attempt evidence", () => {
    const { row, bytes } = fixture();
    expect(generationTerminationPath(row, id)).toBe(`batches/${batch}/generation/terminations/${id}.json`);
    expect(parseGenerationTermination(row, id, bytes, url)).toEqual({ outcome: "generation_model_terminated", usageComplete: false,
      partialTotalTokens: 110, evidenceSha256: row.termination_record_sha256, evidenceUrl: url });
  });
  it("rejects complete cost fields, missing flags, unsafe paths and changed receipts", () => {
    const { row, bytes } = fixture();
    for (const field of ["input_tokens", "cached_tokens", "output_tokens", "total_tokens", "reasoning_output_tokens", "cache_write_input_tokens"]) {
      expect(() => generationTerminationPath({ ...row, [field]: "0" }, id)).toThrow(/presented as complete/);
    }
    expect(() => generationTerminationPath({ ...row, token_usage_complete: "true" }, id)).toThrow(/Unflagged/);
    expect(() => generationTerminationPath({ ...row, token_usage_complete: "unknown" }, id)).toThrow(/completeness/);
    expect(() => generationTerminationPath({ ...row, source_batch: "../escape" }, id)).toThrow(/Unsafe/);
    expect(() => parseGenerationTermination(row, id, bytes + " ", url)).toThrow(/provenance/);
    expect(() => parseGenerationTermination({ ...row, partial_token_counts: JSON.stringify({ ...counts, total_tokens: 111 }) }, id, bytes, url)).toThrow(/partial/);
    expect(() => parseGenerationTermination({ ...row, partial_token_counts: JSON.stringify({ ...counts, cached_input_tokens: 101 }) }, id, bytes, url)).toThrow(/partial/);
  });
  it.each([{ run_id: "another" }, { session_id: "another" }, { approved_by: "automatic" },
    { usage_complete: true }, { native_process_receipt_available: true }])("rejects inconsistent receipts: %j", (extra) => {
    const { row, bytes } = fixture(extra);
    expect(() => parseGenerationTermination(row, id, bytes, url)).toThrow(/receipt/);
  });
});
