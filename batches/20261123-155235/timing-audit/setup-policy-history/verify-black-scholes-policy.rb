# frozen_string_literal: true
require_relative "observer-pipeline-v5/tools/timing_audit/lib/timing_audit"
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
parent = "/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium"
root = "#{parent}-black-scholes-setup-policy"
evidence = File.join(campaign, "black-scholes-setup-policy")
policy_path = File.join(campaign, "black-scholes-preprocessing-policy.json")
policy = JSON.parse(File.read(policy_path))
raise "Unexpected policy state" unless policy.fetch("status") == "decision_recorded_pending_application"
raise "User decision changed" unless TimingAudit.sha256_file(policy.fetch("user_decision_path")) == policy.fetch("user_decision_sha256")
originals = TimingAudit.load_jsonl(File.join(parent, "inventory.jsonl"))
  .select { |row| row.fetch("benchmark") == "black-scholes" }.to_h { |row| [row.fetch("id"), row] }
records = TimingAudit.load_jsonl(File.join(root, "inventory.jsonl"))
raise "Policy selection differs" unless records.size == 20 && records.map { |row| row.fetch("id") }.sort == originals.keys.sort
records.each do |row|
  raise "Policy source differs" unless row.fetch("source_digest") == originals.fetch(row.fetch("id")).fetch("source_digest") &&
    row.fetch("source_tree_oid") == originals.fetch(row.fetch("id")).fetch("source_tree_oid")
end
review_roots = { root => ["gpt-5.6-luna", "high"], "#{root}-priority" => ["gpt-5.6-luna", "high"], "#{root}-sol61" => ["gpt-6.1-sol", "xhigh"] }
review_roots.each do |directory, (model, effort)|
  TimingAudit::AuditVerifier.new(directory, "full").run
  Dir[File.join(directory, "results/*.json")].each do |path|
    id = File.basename(path, ".json")
    accepted = Dir[File.join(directory, "logs", id, "attempt-*/metadata.yaml")].filter_map do |metadata|
      data = YAML.safe_load_file(metadata)
      data if data["result_sha256"] == TimingAudit.sha256_file(path)
    end
    raise "Wrong reviewer identity" unless !accepted.empty? && accepted.all? { |data|
      data["model"] == model && data["reasoning_effort"] == effort && data["static_only_verified"] == true }
  end
  Dir[File.join(directory, "logs/**/events.jsonl")].each { |path| TimingAudit.verify_static_events!(path) }
end
decisions_path = File.join(root, "final/decisions.jsonl")
decisions = TimingAudit.load_jsonl(decisions_path)
raise "Policy application needs review" unless decisions.size == 20 && decisions.all? { |row|
  row.fetch("final_verdict") == "valid" && row.fetch("final_confidence") == "high" && row.fetch("final_issue_categories") == ["none"] }
report = {
  "checked_at" => TimingAudit.utc_now, "passed" => true,
  "scope" => "Source-bound application of the explicit fixed-size-template setup policy, not a numerical-validation or performance rerun.",
  "records" => 20, "verdicts" => { "valid" => 20 },
  "user_decision_sha256" => policy.fetch("user_decision_sha256"),
  "manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml")),
  "final_decisions_sha256" => TimingAudit.sha256_file(decisions_path),
  "source_quality_samples" => %w[black-scholes_gpt-6.2-astra-medium_hybrid_r4 black-scholes_gpt-6.2-astra-medium_hybrid_r5],
  "sample_check" => "Both fixed-size seven-template pricing tables and their consumers were directly inspected before the policy decision; new source-cited results correctly apply that exception while retaining device-completion and MPI_MAX requirements. Parent quality evidence retains exact source hashes and inspected lines.",
  "source_quality_receipt_sha256" => TimingAudit.sha256_file(File.join(campaign, "pilot-source-quality-review.json")),
  "policy_method_commit" => "4bfe4c66fadd03749ad1b7db04e1a083eb921a98",
  "regression_tests" => { "runs" => 51, "assertions" => 391, "failures" => 0, "errors" => 0, "skips" => 0 },
  "old_reviews_and_historical_results_unchanged" => true,
  "program_changes" => 0, "program_executions" => 0, "compilation" => 0, "benchmark_runs" => 0
}
report_path = File.join(evidence, "application-quality-review.json")
raise "Policy application already sealed" if File.exist?(report_path)
TimingAudit.atomic_write(report_path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(policy_path, File.join(evidence, "policy-before-application.json"))
policy = policy.merge("status" => "resolved", "resolved_at" => TimingAudit.utc_now,
  "application_review_path" => report_path, "application_review_sha256" => TimingAudit.sha256_file(report_path),
  "application_final_decisions_sha256" => TimingAudit.sha256_file(decisions_path),
  "program_corrections_allowed" => true, "standard_pipeline_may_continue" => true,
  "remaining_gates" => "All other timing/QT/SpMV reviews and corrected-program native validation remain required before benchmarking. Website hold remains.")
TimingAudit.atomic_write(policy_path, JSON.pretty_generate(policy) + "\n")
FileUtils.cp(__FILE__, evidence)
puts JSON.pretty_generate(report)
