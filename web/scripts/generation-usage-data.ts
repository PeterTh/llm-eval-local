import { createHash } from "node:crypto";
import { z } from "zod";
import type { GenerationUsage } from "../src/data/types";

type Row = Record<string, string | undefined>;
export const TREE_USAGE_SOURCE = "codex_rollout_unique_thread_requests";
const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const countersSchema = z.object({
  input_tokens: count, cached_input_tokens: count, cache_write_input_tokens: count,
  output_tokens: count, reasoning_output_tokens: count, total_tokens: count,
}).strict().refine((x) => x.input_tokens >= x.cached_input_tokens + x.cache_write_input_tokens
  && x.output_tokens >= x.reasoning_output_tokens && x.total_tokens === x.input_tokens + x.output_tokens,
"Inconsistent native usage counters");
const sha = z.string().regex(/^[0-9a-f]{64}$/);
const sessionSchema = z.object({
  session_id: z.string().uuid(), parent_session_id: z.string().uuid().nullable(),
  session_path: z.string().min(1), session_sha256: sha, session_bytes: count.positive(),
  session_cwd: z.string().min(1), cli_version: z.string().min(1),
  model: z.string().min(1), reasoning_effort: z.string().min(1), request_count: count,
  usage: countersSchema, final_task_event: z.string().nullable(),
});
const recordSchema = z.object({
  schema_version: z.literal(2), source: z.literal(TREE_USAGE_SOURCE),
  accounting_scope: z.literal("parent_and_descendants"), batch: z.string().regex(/^\d{8}-\d{6}$/),
  run_id: z.string().regex(/^[a-zA-Z0-9_.-]+$/), session_id: z.string().uuid(),
  session_path: z.string().min(1), session_sha256: sha, transcript_sha256: sha,
  session_cwd: z.string().min(1), cli_version: z.string().min(1),
  model: z.string().min(1), reasoning_effort: z.string().min(1),
  usage: countersSchema, root_usage: countersSchema, request_count: count,
  sessions: z.array(sessionSchema).nonempty(), interrupted_sessions: z.array(z.string().uuid()),
  interrupted_request_usage_uncertain: z.boolean(),
});
type TreeRecord = z.infer<typeof recordSchema>;
type Counters = z.infer<typeof countersSchema>;
const fields = Object.keys(countersSchema.shape) as Array<keyof Counters>;
const csvFields: Record<keyof Counters, string> = {
  input_tokens: "input_tokens", cached_input_tokens: "cached_tokens", cache_write_input_tokens: "cache_write_input_tokens",
  output_tokens: "output_tokens", reasoning_output_tokens: "reasoning_output_tokens", total_tokens: "total_tokens",
};
function invariant(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
function sameCounters(a: Counters, b: Counters): boolean {
  return fields.every((field) => a[field] === b[field]);
}

export function generationUsagePath(row: Row, runId: string): string | null {
  if (row.token_usage_source !== TREE_USAGE_SOURCE) return null;
  invariant(/^\d{8}-\d{6}$/.test(row.source_batch ?? "") && /^[a-zA-Z0-9_.-]+$/.test(runId),
    `Unsafe native tree usage identity: ${runId}`);
  return `metadata/codex-usage/${row.source_batch}.jsonl`;
}

export function parseTreeUsageRecords(bytes: string): Map<string, { record: TreeRecord; sha256: string; line: number }> {
  const result = new Map<string, { record: TreeRecord; sha256: string; line: number }>();
  for (const [index, line] of bytes.split("\n").entries()) {
    if (!line.trim()) continue;
    const record = recordSchema.parse(JSON.parse(line));
    invariant(!result.has(record.run_id), `Duplicate native tree usage: ${record.run_id}`);
    const sessions = new Map(record.sessions.map((session) => [session.session_id, session]));
    invariant(sessions.size === record.sessions.length && new Set(record.sessions.map((s) => s.session_path)).size === sessions.size,
      `Duplicate native tree session: ${record.run_id}`);
    const root = sessions.get(record.session_id);
    invariant(root?.parent_session_id === null && root.final_task_event === "task_complete",
      `Native tree root did not complete: ${record.run_id}`);
    invariant(sameCounters(root.usage, record.root_usage) && root.session_path === record.session_path
      && root.session_sha256 === record.session_sha256, `Native tree root differs: ${record.run_id}`);
    for (const session of record.sessions) {
      invariant(!session.session_path.startsWith("/") && !session.session_path.split("/").some((part) => ["", ".", ".."].includes(part)),
        `Unsafe native archive path: ${record.run_id}`);
      invariant(session.model === record.model && session.reasoning_effort === record.reasoning_effort
        && session.cli_version === record.cli_version && session.session_cwd === record.session_cwd,
      `Native tree model/context differs: ${record.run_id}`);
      let node = session;
      const seen = new Set<string>();
      while (node.session_id !== root.session_id) {
        invariant(!seen.has(node.session_id), `Cyclic native tree: ${record.run_id}`);
        seen.add(node.session_id);
        const parent = node.parent_session_id === null ? undefined : sessions.get(node.parent_session_id);
        invariant(parent, `Disconnected native tree: ${record.run_id}`);
        node = parent;
      }
    }
    invariant(fields.every((field) => record.usage[field] === record.sessions.reduce((sum, s) => sum + s.usage[field], 0))
      && record.request_count === record.sessions.reduce((sum, s) => sum + s.request_count, 0),
    `Native tree totals differ: ${record.run_id}`);
    const interrupted = record.sessions.filter((s) => s.final_task_event !== "task_complete").map((s) => s.session_id);
    invariant(JSON.stringify(interrupted) === JSON.stringify(record.interrupted_sessions)
      && record.interrupted_request_usage_uncertain === (interrupted.length > 0),
    `Native tree interruption flag differs: ${record.run_id}`);
    result.set(record.run_id, { record, line: index + 1, sha256: createHash("sha256").update(line).digest("hex") });
  }
  return result;
}

export function bindGenerationUsage(row: Row, runId: string,
  evidence: ReturnType<typeof parseTreeUsageRecords> extends Map<string, infer T> ? T : never,
  evidenceUrl: string): GenerationUsage {
  const { record, sha256, line } = evidence;
  invariant(generationUsagePath(row, runId) !== null && record.run_id === runId && record.batch === row.source_batch
    && `${record.model}-${record.reasoning_effort}` === row.model && record.session_id === row.token_usage_session_id,
  `Native tree CSV identity differs: ${runId}`);
  const complete = !record.interrupted_request_usage_uncertain;
  invariant(row.token_usage_complete === String(complete) && row.generation_outcome === "completed"
    && !row.generation_failure_reason && !row.termination_record_sha256,
  `Native tree completion differs: ${runId}`);
  invariant(fields.every((field) => {
    const value = row[csvFields[field]];
    return value !== undefined && value.trim() !== "" && Number.isSafeInteger(Number(value)) && Number(value) === record.usage[field];
  }), `Native tree CSV counters differ: ${runId}`);
  invariant(complete ? !row.partial_token_counts : sameCounters(countersSchema.parse(JSON.parse(row.partial_token_counts ?? "null")), record.usage),
    `Native tree partial counters differ: ${runId}`);
  return { source: TREE_USAGE_SOURCE, accountingScope: "parent_and_descendants", usageComplete: complete,
    recordedSessions: record.sessions.length, recordedRequests: record.request_count,
    interruptedSessions: record.interrupted_sessions.length, recordedTotalTokens: record.usage.total_tokens,
    evidenceSha256: sha256, evidenceUrl: `${evidenceUrl}#L${line}` };
}
