# frozen_string_literal: true

$stdout.sync = true
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_audit"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/qtclustering_boundary"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation"
source = "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/generated"
primary = "/home/petert/llm_timing_audit/20261023-deepseek41-opencode"
boundary = "/home/petert/llm_timing_audit/20261023-deepseek41-opencode-qtclustering"
phase = "verify_validation"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "audit-pilot-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "primary" => primary, "qtclustering" => boundary
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  manifest = LocalEvaluation::Manifest.new(validation)
  manifest.verify_input_revisions!
  completion = JSON.parse(File.read(File.join(validation, "validation-completion-review.json")))
  raise "Validation evidence changed" unless completion.fetch("completed") == 220 &&
    completion.fetch("validation_results_sha256") == TimingAudit.sha256_file(File.join(validation, "validation/all_validation_results.yaml"))
  raise "Unexpected validation selection" unless manifest.runs.size == 220 &&
    manifest.runs.values.all? { |record| record.fetch("batch") == "20261019-134042" && record.fetch("model") == "deepseek-v4.1-flash-oc-high" }
  raise "Source revision changed" unless manifest.data.dig("experiment_repository", "commit") == "40ad0bc6da259d4584e75b8f23f43c77e9751b24"
  phase = "prepare_primary"
  checkpoint.call
  unless File.exist?(primary)
    TimingAudit::InventoryBuilder.new(validation_run: validation,
      source_root: source, output_dir: primary, trial_size: 16).run
  end
  phase = "primary_pilot"
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: primary, scope: "trial", jobs: 4,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "prepare_qtclustering"
  checkpoint.call
  unless File.exist?(boundary)
    QtclusteringBoundary::Builder.new(release_root: "/home/petert/llm-eval-local",
      validation_runs: [validation], include_release: false,
      source_root: source, source_commit: "40ad0bc6da259d4584e75b8f23f43c77e9751b24",
      reference_root: "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/benchmarks",
      reference_commit: "2bc11aeac658a87b5cae25d03e0669f65d32922e",
      benchmark_config: "/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml",
      context_path: File.join(validation, "timing-platform-context.txt"),
      output_dir: boundary, trial_size: 16).run
  end
  phase = "qtclustering_pilot"
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: boundary, scope: "trial", jobs: 4,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "qtclustering_pilot_uncertainty_only_sol61"
  checkpoint.call
  QtclusteringBoundary.run_review(main_root: boundary, output_dir: "#{boundary}-sol61", scope: "trial", jobs: 2)
  phase = "qtclustering_pilot_gate"
  checkpoint.call
  raise "QT-clustering pilot quality gate requires investigation" unless
    QtclusteringBoundary.pilot_gate(main_root: boundary, review_root: "#{boundary}-sol61")
  phase = "awaiting_primary_pilot_quality_review"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
