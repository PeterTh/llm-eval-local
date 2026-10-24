# frozen_string_literal: true

require "json"
require "open3"
require_relative "experiment/tools/timing_audit/bin/export_validation_audit"
require_relative "benchmark-export"
require_relative "release/tools/export_opencode_supplement"

scratch = __dir__
root = File.join(scratch, "release")
batch = File.join(root, "batches/20261019-134042")
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
native = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation"
audit = "/home/petert/llm_timing_audit/20261023-deepseek41-opencode"
report = JSON.parse(File.read(File.join(campaign, "benchmark-completion-review.json")))
raise "Benchmark completion not verified" unless report.fetch("verification") == "passed" && report.fetch("completed") == 218 && report.fetch("all_records_reconciled")
state, status = Open3.capture2("systemctl", "--user", "show", "llm-deepseek41-oc-benchmark-20261023.service", "--property=ActiveState", "--value")
raise "Measurements still active" unless status.success? && !%w[active activating deactivating].include?(state.strip)
raise "Batch already exported" if File.exist?(batch)
validation = JSON.parse(File.read(File.join(campaign, "validation-completion-review.json")))
raise "Validation changed" unless validation.fetch("completed") == 220 && validation.fetch("passed") == 218 &&
  validation.fetch("validation_results_sha256") == TimingAudit.sha256_file(File.join(native, "validation/all_validation_results.yaml"))
ValidationAuditExport.run(run_dir: native, output_dir: batch, primary: audit,
  priority: "#{audit}-priority", adjudication: "#{audit}-sol61")
OpenCodeSupplement.run(root: root, home: "/home/petert", phase: "audit", batch_id: "20261019-134042")
TimingCorrectionExport.run(batch_dir: batch,
  proposal_root: "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-proposals",
  review_root: "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review",
  adjudication_root: "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review-sol61",
  final_root: "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-final",
  validation_run: "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-corrected",
  original_source: File.join(scratch, "original-backup"),
  audit_selection: File.join(batch, "timing-audit/resolved-selection.json"))
BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,
  conditional_decisions: File.join(batch, "timing-audit/conditional-decisions.jsonl"))
raise "Metadata export amendment failed" unless system(RbConfig.ruby, File.join(scratch, "apply-aggregate-export-amendment.rb"))
raise "Native aggregate failed" unless system(RbConfig.ruby, File.join(scratch, "local-evaluation-driver.rb"), "aggregate", "--run-dir=#{native}")
raise "Aggregate import failed" unless system(RbConfig.ruby, File.join(root, "tools/import_batch_aggregate.rb"), "--native-run=#{native}", "--batch=20261019-134042")
OpenCodeSupplement.run(root: root, home: "/home/petert", phase: "complete", batch_id: "20261019-134042")
receipt = {
  "exported_at" => TimingAudit.utc_now, "batch" => "20261019-134042", "records" => 220,
  "benchmarks" => report.fetch("completed"), "successful" => report.fetch("successful"),
  "corrections" => report.fetch("timing_fixed_records"), "release_workspace" => root,
  "completion_report_sha256" => TimingAudit.sha256_file(File.join(campaign, "benchmark-completion-review.json")),
  "driver_sha256" => TimingAudit.sha256_file(__FILE__),
  "supplement_sha256" => TimingAudit.sha256_file(File.join(root, "tools/export_opencode_supplement.rb")),
  "policy" => "Compact native evidence export only. Combined scoring, new-winner analysis, package/site checks and publication are separate gates."
}
TimingAudit.atomic_write(File.join(campaign, "batch-export.json"), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
