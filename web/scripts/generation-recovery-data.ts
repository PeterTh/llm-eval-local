import { createHash } from "node:crypto";
import type { GenerationTimeRecovery } from "../src/data/types";
import { parseGenerationTime } from "./time-data";

type Row = Record<string, string | undefined>;

export function generationRecoveryPath(row: Row, runId: string): string | null {
  const flag = row.generation_time_recovered ?? "";
  if (!["", "false", "true"].includes(flag)) throw new Error(`Invalid generation recovery flag: ${runId}`);
  if (flag !== "true") {
    if (row.generation_time_source || row.generation_recovery_sha256 || row.wrapper_exit_status_available) {
      throw new Error(`Unflagged generation recovery metadata: ${runId}`);
    }
    return null;
  }
  if (!/^\d{8}-\d{6}$/.test(row.source_batch ?? "") || !/^[a-zA-Z0-9_.-]+$/.test(runId)) {
    throw new Error(`Unsafe generation recovery identity: ${runId}`);
  }
  return `batches/${row.source_batch}/generation/recoveries/${runId}.json`;
}

export function parseGenerationRecovery(row: Row, runId: string, bytes: string, evidenceUrl: string): GenerationTimeRecovery {
  if (generationRecoveryPath(row, runId) === null) throw new Error(`Unexpected recovery receipt: ${runId}`);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (row.generation_time_source !== "claude_result_duration_ms" || row.wrapper_exit_status_available !== "false"
    || !/^[0-9a-f]{64}$/.test(row.generation_recovery_sha256 ?? "") || sha256 !== row.generation_recovery_sha256) {
    throw new Error(`Generation recovery provenance mismatch: ${runId}`);
  }
  const receipt = JSON.parse(bytes);
  const seconds = parseGenerationTime(row.total_time, runId);
  if (receipt.schema_version !== 1 || receipt.run_id !== runId || receipt.campaign_id !== row.source_batch
    || receipt.approved_by !== "user" || receipt.decision !== "retain_completed_native_result"
    || receipt.generation_time_source !== row.generation_time_source || receipt.generation_time_recovered !== true
    || receipt.wrapper_exit_status_available !== false || receipt.wrapper_wall_time_seconds !== null
    || receipt.wrapper_start_time !== null || receipt.wrapper_end_time !== null
    || !Number.isSafeInteger(receipt.duration_ms) || receipt.duration_ms <= 0 || seconds === null
    || Math.abs(receipt.duration_ms / 1000 - seconds) > 1e-9) {
    throw new Error(`Generation recovery receipt mismatch: ${runId}`);
  }
  return { source: "claude_result_duration_ms", wrapperExitStatusAvailable: false, evidenceSha256: sha256, evidenceUrl };
}
