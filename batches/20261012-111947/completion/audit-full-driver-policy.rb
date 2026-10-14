# frozen_string_literal: true

$stdout.sync = true
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/review-method/tools/timing_audit/bin/timing_priority_review"
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/review-method/tools/timing_audit/bin/timing_finalize_audit"
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/review-method/tools/timing_audit/lib/qtclustering_boundary"

campaign = "/home/petert/llm_para_campaigns/20261012-111947-haiku55-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261014-haiku55"
priority = "#{primary}-priority"
adjudication = "#{primary}-sol61"
boundary = "#{primary}-qtclustering"
context = "/home/petert/llm_para_local_evaluation/20261014-haiku55-validation/timing-platform-context.txt"
phase = "verify_pilot_gate"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "audit-full-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  policy = JSON.parse(File.read(File.join(campaign, "review-policy-continuation.json")))
  raise "Unexpected review policy" unless policy.fetch("policy") == QtclusteringBoundary::REVIEW_POLICY
  policy.fetch("retained_results").each do |path, digest|
    raise "Completed review changed: #{path}" unless TimingAudit.sha256_file(path) == digest
  end
  policy.fetch("method_files").each do |path, digest|
    raise "Review method changed: #{path}" unless TimingAudit.sha256_file(path) == digest
  end
  pilot = JSON.parse(File.read(File.join(primary, "pilot-review.json")))
  raise "Primary pilot gate missing or stale" unless pilot.fetch("passed") &&
    pilot.fetch("inventory_sha256") == TimingAudit.sha256_file(File.join(primary, "inventory.jsonl")) &&
    pilot.fetch("trial_ids_sha256") == TimingAudit.sha256_file(File.join(primary, "trial-ids.txt"))
  raise "QT-clustering pilot gate did not pass" unless
    JSON.parse(File.read(File.join(boundary, "pilot-review.json"))).fetch("passed")
  phase = "primary_full"
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: primary, scope: "full", jobs: 16,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "independent_review"
  checkpoint.call
  TimingPriorityReview.prepare(main_root: primary, output_dir: priority) unless File.exist?(priority)
  TimingPriorityReview.run(output_dir: priority, jobs: 16)
  TimingAudit::AuditVerifier.new(priority, "full").run
  phase = "sol61_adjudication"
  checkpoint.call
  unless File.exist?(adjudication)
    TimingPriorityReview.prepare_adjudication(main_root: primary, review_root: priority,
      output_dir: adjudication, context_path: context, model: "gpt-6.1-sol")
  end
  TimingAudit::AuditRunner.new(output_dir: adjudication, scope: "full", jobs: 2,
    model: "gpt-6.1-sol", effort: "xhigh").run
  phase = "finalize_mpi_hybrid"
  checkpoint.call
  TimingFinalizeAudit.run(main_root: primary, priority_root: priority, adjudication_root: adjudication)
  phase = "qtclustering_full"
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: boundary, scope: "full", jobs: 16,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "qtclustering_uncertainty_only_sol61"
  checkpoint.call
  QtclusteringBoundary.run_review(main_root: boundary, output_dir: "#{boundary}-sol61", scope: "full", jobs: 2)
  phase = "finalize_qtclustering"
  checkpoint.call
  unless File.directory?(File.join(boundary, "final"))
    QtclusteringBoundary.finalize(main_root: boundary, review_root: "#{boundary}-sol61")
  end
  phase = "awaiting_correction_review"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
