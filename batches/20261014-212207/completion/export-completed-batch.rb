# frozen_string_literal: true

# Only runs after benchmark completion; all source programs and measurements
# remain in their native repositories. This exports compact retained evidence.
require "/tmp/sonnet55-evaluation-20261015.FtsY7h/experiment/tools/timing_audit/bin/export_timing_corrections"
require "/tmp/sonnet55-evaluation-20261015.FtsY7h/benchmark-export"
require "/tmp/sonnet55-evaluation-20261015.FtsY7h/release/tools/export_sonnet55_supplement"

scratch = File.dirname(__FILE__)
root = File.join(scratch, "release")
batch = File.join(root, "batches/20261014-212207")
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
native = "/home/petert/llm_para_local_evaluation/20261015-sonnet55-validation"
report = JSON.parse(File.read(File.join(campaign, "benchmark-completion-review.json")))
raise "Benchmark completion not verified" unless report.fetch("verification") == "passed" && report.fetch("completed") == 215 && report.fetch("all_records_reconciled")
raise "Completed batch export already exists" if File.exist?(File.join(batch, "aggregate/export.json"))
TimingCorrectionExport.run(batch_dir: batch,
  proposal_root: "/home/petert/llm_timing_fixes/20261015-sonnet55-proposals",
  review_root: "/home/petert/llm_timing_fixes/20261015-sonnet55-review",
  adjudication_root: "/home/petert/llm_timing_fixes/20261015-sonnet55-review-sol61",
  final_root: "/home/petert/llm_timing_fixes/20261015-sonnet55-final",
  validation_run: "/home/petert/llm_para_local_evaluation/20261015-sonnet55-corrected",
  original_source: File.join(scratch, "original-backup"),
  audit_selection: File.join(batch, "timing-audit/resolved-selection.json"))
BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,
  conditional_decisions: File.join(batch, "timing-audit/conditional-decisions.jsonl"))
raise "Native aggregate failed" unless system(RbConfig.ruby, File.join(scratch, "local-evaluation-driver.rb"), "aggregate", "--run-dir=#{native}")
raise "Aggregate import failed" unless system(RbConfig.ruby, File.join(root, "tools/import_batch_aggregate.rb"), "--native-run=#{native}", "--batch=20261014-212207")
Sonnet55Supplement.run(root: root, home: "/home/petert", phase: "complete")
receipt = {
  "exported_at" => TimingAudit.utc_now, "batch" => "20261014-212207", "records" => 220,
  "benchmarks" => report.fetch("completed"), "successful" => report.fetch("successful"),
  "corrections" => report.fetch("timing_fixed_records"), "release_workspace" => root,
  "completion_report_sha256" => TimingAudit.sha256_file(File.join(campaign, "benchmark-completion-review.json")),
  "driver_sha256" => TimingAudit.sha256_file(__FILE__),
  "supplement_sha256" => TimingAudit.sha256_file(File.join(root, "tools/export_sonnet55_supplement.rb")),
  "policy" => "Compact native evidence export only. Combined scoring, new-winner analysis, final website/package checks and publication remain separate gates."
}
TimingAudit.atomic_write(File.join(campaign, "batch-export.json"), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
