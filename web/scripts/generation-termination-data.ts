import { createHash } from "node:crypto";
import type { GenerationTermination } from "../src/data/types";

type Row = Record<string, string | undefined>;
const fullFields = ["input_tokens", "cached_tokens", "output_tokens", "total_tokens", "reasoning_output_tokens", "cache_write_input_tokens"];
const partialFields = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"];

export function generationTerminationPath(row: Row, runId: string): string | null {
  const flag = row.token_usage_complete ?? "";
  if (!["", "true", "false"].includes(flag)) throw new Error(`Invalid usage completeness: ${runId}`);
  if (flag !== "false") {
    if (row.partial_token_counts || row.generation_failure_reason || row.termination_record_sha256
      || !["", "completed"].includes(row.generation_outcome ?? "")) {
      throw new Error(`Unflagged generation termination: ${runId}`);
    }
    return null;
  }
  if (!/^\d{8}-\d{6}$/.test(row.source_batch ?? "") || !/^[a-zA-Z0-9_.-]+$/.test(runId)) {
    throw new Error(`Unsafe generation termination identity: ${runId}`);
  }
  if (row.generation_outcome !== "generation_model_terminated" || row.generation_failure_reason !== "model_caused_termination"
    || row.token_usage_source !== "opencode_native_step_finish" || fullFields.some((field) => Boolean(row[field]))) {
    throw new Error(`Incomplete generation usage presented as complete: ${runId}`);
  }
  return `batches/${row.source_batch}/generation/terminations/${runId}.json`;
}

export function parseGenerationTermination(row: Row, runId: string, bytes: string, evidenceUrl: string): GenerationTermination {
  if (generationTerminationPath(row, runId) === null) throw new Error(`Unexpected termination receipt: ${runId}`);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (!/^[0-9a-f]{64}$/.test(row.termination_record_sha256 ?? "") || sha256 !== row.termination_record_sha256) {
    throw new Error(`Generation termination provenance mismatch: ${runId}`);
  }
  const receipt = JSON.parse(bytes);
  if (receipt.schema_version !== 1 || receipt.run_id !== runId || receipt.session_id !== row.token_usage_session_id
    || receipt.approved_by !== "user" || receipt.decision !== "retain_original_without_restart"
    || receipt.reason !== "model_caused_termination" || receipt.usage_complete !== false
    || receipt.native_process_receipt_available !== false) {
    throw new Error(`Generation termination receipt mismatch: ${runId}`);
  }
  const counts: Record<string, number> = JSON.parse(row.partial_token_counts ?? "null");
  if (!counts || partialFields.some((field) => !Number.isSafeInteger(counts[field]) || counts[field]! < 0)
    || counts.input_tokens! < counts.cached_input_tokens! + counts.cache_write_input_tokens!
    || counts.output_tokens! < counts.reasoning_output_tokens!
    || counts.total_tokens! !== counts.input_tokens! + counts.output_tokens! || counts.total_tokens! <= 0) {
    throw new Error(`Invalid partial generation counters: ${runId}`);
  }
  return { outcome: "generation_model_terminated", usageComplete: false, partialTotalTokens: counts.total_tokens!,
    evidenceSha256: sha256, evidenceUrl };
}
