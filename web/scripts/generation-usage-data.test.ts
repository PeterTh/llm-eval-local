import { describe, expect, it } from "vitest";
import { bindGenerationUsage, generationUsagePath, parseTreeUsageRecords, TREE_USAGE_SOURCE } from "./generation-usage-data";
import { generationTerminationPath } from "./generation-termination-data";

const id = "spmv_gpt-6.1-terra-ultra_omp_r1";
const rootId = "01a1ac33-ab99-7401-90a3-7d42390d3b30";
const childId = "01a1ac33-ab99-7401-90a3-7d42390d3b31";
const usage = { input_tokens: 100, cached_input_tokens: 80, cache_write_input_tokens: 0,
  output_tokens: 10, reasoning_output_tokens: 4, total_tokens: 110 };
function fixture(interrupted = false) {
  const common = { session_cwd: "/tmp/observation", cli_version: "0.160.1", model: "gpt-6.1-terra", reasoning_effort: "ultra" };
  const session = { ...common, session_id: rootId, parent_session_id: null, session_path: "root.jsonl", session_sha256: "a".repeat(64),
    session_bytes: 1000, request_count: 2, usage, final_task_event: "task_complete" };
  const total = Object.fromEntries(Object.entries(usage).map(([key, value]) => [key, value * 2]));
  const record = { ...common, schema_version: 2, source: TREE_USAGE_SOURCE, accounting_scope: "parent_and_descendants",
    batch: "20261105-131145", run_id: id, session_id: rootId, session_path: "root.jsonl", session_sha256: "a".repeat(64),
    transcript_sha256: "b".repeat(64), root_usage: usage, usage: total, request_count: 4,
    sessions: [session, { ...session, session_id: childId, parent_session_id: rootId, session_path: "child.jsonl", final_task_event: interrupted ? "task_aborted" : "task_complete" }],
    interrupted_sessions: interrupted ? [childId] : [], interrupted_request_usage_uncertain: interrupted };
  const row = { source_batch: record.batch, model: "gpt-6.1-terra-ultra", token_usage_source: TREE_USAGE_SOURCE,
    token_usage_session_id: rootId, token_usage_complete: String(!interrupted), generation_outcome: "completed",
    input_tokens: "200", cached_tokens: "160", cache_write_input_tokens: "0", output_tokens: "20", reasoning_output_tokens: "8", total_tokens: "220",
    partial_token_counts: interrupted ? JSON.stringify(total) : "" };
  const bind = () => bindGenerationUsage(row, id, parseTreeUsageRecords(JSON.stringify(record)).get(id)!, "https://example.test/usage.jsonl");
  return { record, row, bind };
}

describe("recorded native parent-and-child usage", () => {
  it("sums both sessions and binds complete usage to the CSV", () => {
    const { row, bind } = fixture();
    expect(generationUsagePath(row, id)).toBe("metadata/codex-usage/20261105-131145.jsonl");
    expect(bind()).toMatchObject({ usageComplete: true, recordedSessions: 2, recordedRequests: 4, recordedTotalTokens: 220, interruptedSessions: 0 });
    expect(generationTerminationPath(row, id, bind())).toBeNull();
    expect(() => generationTerminationPath(row, id)).toThrow(/bound evidence/);
  });
  it("retains interrupted-child uncertainty without claiming a failed generation", () => {
    const { row, bind } = fixture(true);
    expect(bind()).toMatchObject({ usageComplete: false, interruptedSessions: 1, recordedTotalTokens: 220 });
    expect(generationTerminationPath(row, id, bind())).toBeNull();
    row.token_usage_complete = "true";
    expect(bind).toThrow(/completion/);
  });
  it("rejects missing explicit counters and understated partial counts", () => {
    const { row, bind } = fixture(true);
    row.partial_token_counts = JSON.stringify(usage);
    expect(bind).toThrow(/partial counters/);
    const full = fixture();
    full.row.cache_write_input_tokens = "";
    expect(full.bind).toThrow(/CSV counters/);
  });
  it("rejects broken ownership, duplicate sessions, missing interruptions and incorrect totals", () => {
    for (const mutate of [
      (r: ReturnType<typeof fixture>["record"]) => { r.sessions[1]!.parent_session_id = childId; },
      (r: ReturnType<typeof fixture>["record"]) => { r.sessions[1]!.session_id = rootId; },
      (r: ReturnType<typeof fixture>["record"]) => { r.interrupted_sessions = []; },
      (r: ReturnType<typeof fixture>["record"]) => { r.request_count = 2; },
      (r: ReturnType<typeof fixture>["record"]) => { r.sessions[1]!.model = "wrong-model"; },
    ]) {
      const { record } = fixture(true);
      mutate(record);
      expect(() => parseTreeUsageRecords(JSON.stringify(record))).toThrow();
    }
  });
  it("rejects mismatched CSV identity and unsafe paths", () => {
    const { row, bind } = fixture();
    row.token_usage_session_id = childId;
    expect(bind).toThrow(/identity/);
    row.source_batch = "../escape";
    expect(() => generationUsagePath(row, id)).toThrow(/Unsafe/);
  });
});
