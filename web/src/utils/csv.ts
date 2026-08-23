import type { RunRecord } from "../data/types";

function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function runsToCsv(runs: readonly RunRecord[]): string {
  const headers = [
    "id", "model", "benchmark", "backend", "repetition", "overall_score",
    "score_band", "validation_status", "benchmark_success", "benchmark_median_ms",
    "source_url", "validation_evidence_url", "benchmark_evidence_url",
  ];
  const rows = runs.map((run) => [
    run.id,
    run.modelId,
    run.benchmarkId,
    run.backendId,
    run.repetition,
    run.overallScore,
    run.scoreBandId,
    run.validationStatus,
    run.benchmarkSuccess,
    run.benchmarkMedianMs,
    run.sourceUrl,
    run.validationEvidenceUrl,
    run.benchmarkEvidenceUrl,
  ].map(csvCell).join(","));
  return `${headers.join(",")}\n${rows.join("\n")}\n`;
}

export function downloadText(filename: string, content: string, type: string): void {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}
