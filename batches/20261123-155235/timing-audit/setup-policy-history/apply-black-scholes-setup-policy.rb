# frozen_string_literal: true
$stdout.sync = true
require_relative "observer-pipeline-v5/tools/timing_audit/bin/timing_priority_review"
require_relative "observer-pipeline-v5/tools/timing_audit/bin/timing_finalize_audit"

campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
parent = "/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium"
root = "#{parent}-black-scholes-setup-policy"
priority = "#{root}-priority"
adjudication = "#{root}-sol61"
policy_path = File.join(campaign, "black-scholes-preprocessing-policy.json")
phase = "retain_user_decision"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "black-scholes-policy-progress.json"),
    JSON.pretty_generate({ "updated_at" => TimingAudit.utc_now, "pid" => Process.pid,
      "phase" => phase, "root" => root, "driver_sha256" => TimingAudit.sha256_file(__FILE__) }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  evidence = File.join(campaign, "black-scholes-setup-policy")
  raise "Policy application already exists" if File.exist?(root) || File.exist?(evidence)
  FileUtils.mkdir_p(evidence)
  FileUtils.cp(__FILE__, evidence)
  previous = JSON.parse(File.read(policy_path))
  raise "Unexpected prior policy state" unless previous.fetch("status") == "awaiting_user_decision"
  FileUtils.cp(policy_path, File.join(evidence, "initial-policy-hold.json"))
  decision = {
    "recorded_at" => TimingAudit.utc_now,
    "authority" => "Explicit user reply in the active conversation",
    "user_answer" => "Preserve established treatment for fixed-size template setup (recommended for consistency)",
    "scope" => "Fixed-size Black-Scholes template setup, consistent with explicitly documented accepted historical implementations. This does not exempt input-size-dependent preprocessing or defective rank/device timing.",
    "prior_hold_sha256" => TimingAudit.sha256_file(policy_path),
    "no_historical_program_or_benchmark_changes" => true,
    "website_hold" => "Unchanged: discuss default visible set before any website updates."
  }
  decision_path = File.join(evidence, "user-decision.json")
  TimingAudit.atomic_write(decision_path, JSON.pretty_generate(decision) + "\n")
  pending = previous.merge("status" => "decision_recorded_pending_application",
    "user_decision_path" => decision_path, "user_decision_sha256" => TimingAudit.sha256_file(decision_path),
    "application_root" => root)
  TimingAudit.atomic_write(policy_path, JSON.pretty_generate(pending) + "\n")
  records = TimingAudit.load_jsonl(File.join(parent, "inventory.jsonl"))
    .select { |record| record.fetch("benchmark") == "black-scholes" }
  raise "Unexpected policy-review scope" unless records.size == 20 &&
    records.all? { |record| %w[mpi hybrid].include?(record.fetch("par_type")) }
  TimingAudit.derive_inventory(parent_root: parent, output_dir: root,
    ids: records.map { |record| record.fetch("id") }, provenance: {
      "user_authorized_setup_policy" => decision.merge("decision_sha256" => TimingAudit.sha256_file(decision_path)),
      "scope" => "Every validated MPI/hybrid Black-Scholes implementation in this new batch; no previous results overwritten."
    })
  context = File.read(File.join(__dir__, "timing-platform-context.txt"))
  context += <<~POLICY

    USER-AUTHORIZED FIXED-SIZE TEMPLATE SETUP POLICY

    The user explicitly chose to preserve the established treatment of fixed-size
    Black-Scholes template setup. This clarification takes precedence over any
    generic wording that would otherwise require timing this particular setup.
    A table of pricing coefficients/probabilities/base prices for a fixed number
    of input-generator templates, independent of requested option count, may be
    prepared outside the timer, as in documented accepted historical results.
    Do not flag that fact alone as incomplete_timed_region. Explain its exact
    fixed-size nature and cite the producer and consumer in notes/evidence.

    This is NOT a blanket preprocessing exemption. Option-count-dependent
    numerical computation, producing the requested outputs, every rank's complete
    local work and device completion, correct rank aggregation and reported units
    still require the normal review. Data generation/allocation and final collection
    retain their established boundaries. Judge each source, including dispatch,
    rather than assuming it uses the permitted fixed-size scheme. Independent
    complete-result replicas retain their existing rule. No prior verdict is
    supplied. No program execution, compilation, source changes, or performance
    results are involved. Historical data will not change under this decision.
  POLICY
  context_path = File.join(evidence, "policy-context.txt")
  TimingAudit.atomic_write(context_path, context)
  TimingPriorityReview.add_equivalence_review_guidance(root)
  TimingPriorityReview.add_platform_context(root, context_path)
  phase = "luna_policy_review"
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 4,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "independent_uncertainty_or_defect_review"
  checkpoint.call
  TimingPriorityReview.prepare(main_root: root, output_dir: priority)
  TimingPriorityReview.run(output_dir: priority, jobs: 4)
  TimingAudit::AuditVerifier.new(priority, "full").run
  phase = "uncertainty_only_sol61"
  checkpoint.call
  TimingPriorityReview.prepare_adjudication(main_root: root, review_root: priority,
    output_dir: adjudication, context_path: context_path, model: "gpt-6.1-sol")
  TimingAudit::AuditRunner.new(output_dir: adjudication, scope: "full", jobs: 2,
    model: "gpt-6.1-sol", effort: "xhigh").run
  phase = "finalize_policy_overlay"
  checkpoint.call
  TimingFinalizeAudit.run(main_root: root, priority_root: priority, adjudication_root: adjudication)
  phase = "awaiting_policy_application_quality_review"
  checkpoint.call("original_reviews_unchanged" => true, "program_changes" => 0, "benchmark_runs" => 0)
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
