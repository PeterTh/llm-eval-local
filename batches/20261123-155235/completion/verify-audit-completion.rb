# frozen_string_literal: true

require "/tmp/gpt62-medium-evaluation-20261125-ozfKL7/observer-pipeline-v5/tools/timing_audit/lib/timing_audit"
primary = "/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium"
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
policy_path = File.join(campaign, "review-policy.json")
policy = JSON.parse(File.read(policy_path))
raise "Wrong review policy" unless policy.fetch("policy") == "luna_first_uncertainty_or_disagreement_v1"
policy.fetch("retained_results").each do |path, digest|
  raise "Completed pilot evidence changed" unless TimingAudit.sha256_file(path) == digest
end
qt_plan_path = File.join(primary + "-qtclustering-sol61", "adjudication-plan-full.json")
qt_plan = JSON.parse(File.read(qt_plan_path))
raise "QT selection uses obsolete policy" unless qt_plan.fetch("policy") == policy.fetch("policy")
boundary_policy_path = File.join(campaign, "black-scholes-preprocessing-policy.json")
boundary_policy = JSON.parse(File.read(boundary_policy_path))
raise "Setup policy is unresolved" unless boundary_policy.fetch("status") == "resolved"
setup_root = "#{primary}-black-scholes-setup-policy"
raise "Unexpected policy overlay" unless boundary_policy.fetch("application_root") == setup_root &&
  TimingAudit.sha256_file(boundary_policy.fetch("application_review_path")) == boundary_policy.fetch("application_review_sha256") &&
  TimingAudit.sha256_file(File.join(setup_root, "final/decisions.jsonl")) == boundary_policy.fetch("application_final_decisions_sha256") &&
  TimingAudit.sha256_file(boundary_policy.fetch("user_decision_path")) == boundary_policy.fetch("user_decision_sha256")
models = {
  primary => ["gpt-5.6-luna", "high"],
  "#{primary}-priority" => ["gpt-5.6-luna", "high"],
  "#{primary}-sol61" => ["gpt-6.1-sol", "xhigh"],
  "#{primary}-qtclustering" => ["gpt-5.6-luna", "high"],
  "#{primary}-qtclustering-sol61" => ["gpt-6.1-sol", "xhigh"],
  setup_root => ["gpt-5.6-luna", "high"],
  "#{setup_root}-priority" => ["gpt-5.6-luna", "high"],
  "#{setup_root}-sol61" => ["gpt-6.1-sol", "xhigh"],
  "#{primary}-cross-review-sol61" => ["gpt-6.1-sol", "xhigh"]
}
reports = models.map do |root, (model, effort)|
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: model, effort: effort)
  verifier = TimingAudit::AuditVerifier.new(root, "full")
  paths = Dir[File.join(root, "results/*.json")].sort
  paths.each do |path|
    response = JSON.parse(File.read(path))
    id = response.fetch("program_id")
    verifier.verify_result!(id, response)
    accepted = Dir[File.join(root, "logs", id, "attempt-*/metadata.yaml")].filter_map do |metadata_path|
      data = YAML.safe_load_file(metadata_path)
      data if data["result_sha256"] == TimingAudit.sha256_file(path)
    end
    raise "Unbound response for #{id}" if accepted.empty?
    raise "Wrong model or effort for #{id}" unless accepted.all? { |row|
      row.fetch("model") == model && row.fetch("reasoning_effort") == effort && row.fetch("static_only_verified") == true
    }
  end
  events = Dir[File.join(root, "logs/**/events.jsonl")]
  events.each do |path|
    File.foreach(path) do |line|
      item = JSON.parse(line)["item"]
      raise "Prohibited tool event in #{path}" if item && !%w[agent_message reasoning error].include?(item["type"])
    end
  end
  { "root" => root, "model" => model, "effort" => effort, "responses" => paths.size,
    "retained_attempts" => events.size, "nonempty_event_streams" => events.count { |path| !File.zero?(path) },
    "prohibited_tool_events" => 0,
    "manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml")) }
end
decisions = {}
source_digests = {}
inputs = { policy_path => TimingAudit.sha256_file(policy_path), qt_plan_path => TimingAudit.sha256_file(qt_plan_path) }
overlay_changes = []
resolved_policy_changes = []
cross_root = "#{primary}-cross-review-sol61"
decision_roots = [primary, "#{primary}-qtclustering", setup_root, cross_root]
decision_roots.each do |root|
  path = File.join(root, "final/decisions.jsonl")
  inputs[path] = TimingAudit.sha256_file(path)
  TimingAudit.load_jsonl(path).each do |row|
    id = row.fetch("program_id")
    digest = row.fetch("source_digest")
    raise "Overlay source mismatch for #{id}" if source_digests.key?(id) && source_digests.fetch(id) != digest
    if decisions[id] && decisions.fetch(id).fetch("final_verdict") != row.fetch("final_verdict")
      change = { "program_id" => id, "primary_verdict" => decisions.fetch(id).fetch("final_verdict"),
        "boundary_verdict" => row.fetch("final_verdict"), "boundary_basis" => row.fetch("decision_basis"),
        "primary_categories" => decisions.fetch(id).fetch("final_issue_categories"),
        "boundary_categories" => row.fetch("final_issue_categories") }
      if root == setup_root && row.fetch("benchmark") == "black-scholes" &&
          row.fetch("final_verdict") == "valid" && row.fetch("final_confidence") == "high" &&
          (change.fetch("primary_categories") - ["incomplete_timed_region"]).empty?
        resolved_policy_changes << change.merge("basis" => "Explicit user-authorized fixed-size-template setup policy and same-source reviewed overlay")
      else
        overlay_changes << change
      end
    end
    source_digests[id] = digest
    decisions[id] = row
  end
end
overlap_origin = File.join(campaign, "audit-completion-before-cross-review.json")
overlap_prior = JSON.parse(File.read(overlap_origin))
overlap_prior.fetch("input_sha256").each do |path, digest|
  raise "Pre-reconciliation audit input changed" unless TimingAudit.sha256_file(path) == digest
end
overlap_ids = overlap_prior.fetch("overlay_verdict_changes").map { |row| row.fetch("program_id") }.uniq.sort
overlap_final = File.join(cross_root, "final/decisions.jsonl")
overlap_rows = TimingAudit.load_jsonl(overlap_final)
raise "Cross-review scope differs" unless overlap_ids == ["qtclustering_gpt-6.2-sol-medium_hybrid_r3"] &&
  overlap_rows.map { |row| row.fetch("program_id") }.sort == overlap_ids
overlap_manifest = YAML.safe_load_file(File.join(cross_root, "manifest.yaml"))
raise "Cross-review origin differs" unless overlap_manifest.dig("cross_review_reconciliation", "prior_completion_report_sha256") == TimingAudit.sha256_file(overlap_origin)
overlap_manifest.fetch("cross_review_reconciliation").fetch("input_sha256").each do |path, digest|
  raise "Conflicting input review changed" unless TimingAudit.sha256_file(path) == digest
end
overlap_metadata_path = File.join(cross_root, "final/metadata.yaml")
overlap_metadata = YAML.safe_load_file(overlap_metadata_path)
raise "Cross-review finalization changed" unless overlap_metadata.fetch("decisions_sha256") == TimingAudit.sha256_file(overlap_final) &&
  overlap_metadata.fetch("manifest_sha256") == TimingAudit.sha256_file(File.join(cross_root, "manifest.yaml")) &&
  overlap_metadata.fetch("response_sha256") == TimingAudit.sha256_file(File.join(cross_root, "results", overlap_ids.fetch(0) + ".json"))
raise "Cross-review not resolved" unless overlap_rows.all? { |row|
  row.fetch("decision_basis") == "sol_6_1_cross_review_reconciliation" && row.fetch("final_confidence") == "high" &&
  %w[valid invalid].include?(row.fetch("final_verdict")) && (row.fetch("final_verdict") != "invalid" || row.fetch("timing_only_fix_possible")) }
resolved_cross_review_changes, overlay_changes = overlay_changes.partition { |row| overlap_ids.include?(row.fetch("program_id")) }
inputs[overlap_origin] = TimingAudit.sha256_file(overlap_origin)
inputs[overlap_metadata_path] = TimingAudit.sha256_file(overlap_metadata_path)
require "/tmp/gpt62-medium-evaluation-20261125-ozfKL7/observer-pipeline-v5/lib/local_evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v5"
completion = JSON.parse(File.read(File.join(validation, "validation-completion-review.json")))
raise "Original validation changed" unless completion.fetch("validation_results_sha256") ==
  LocalEvaluation.sha256_file(File.join(validation, "validation/all_validation_results.yaml"))
native = LocalEvaluation::ValidationPipeline.new(run_dir: validation).send(:load_results)
expected = native.values.select { |row|
  row.output_comparison && (%w[mpi hybrid].include?(row.par_type) || row.benchmark == "qtclustering")
}.map(&:id_string).sort
raise "Combined audit coverage changed" unless decisions.keys.sort == expected
unresolved = decisions.values.select { |row|
  row.fetch("final_verdict") == "ambiguous" || row.fetch("final_confidence") != "high" ||
    (row.fetch("final_verdict") == "invalid" && !row.fetch("timing_only_fix_possible"))
}
inputs[boundary_policy_path] = TimingAudit.sha256_file(boundary_policy_path)
pending_policy = boundary_policy.fetch("status") == "resolved" ? nil : boundary_policy
report = {
  "checked_at" => TimingAudit.utc_now, "passed" => unresolved.empty? && overlay_changes.empty? && pending_policy.nil?,
  "decision_roots" => decision_roots,
  "pending_policy" => pending_policy,
  "resolved_policy_changes" => resolved_policy_changes,
  "resolved_cross_review_changes" => resolved_cross_review_changes,
  "cross_review_reconciliation" => { "root" => cross_root, "records" => overlap_ids.size,
    "reason" => "Only the retained same-source general/QT verdict disagreement; source-only Sol-6.1 reconciliation under the unchanged contract." },
  "unique_programs" => decisions.size, "reviews" => reports, "input_sha256" => inputs,
  "verdicts" => decisions.values.map { |row| row.fetch("final_verdict") }.tally,
  "corrections_by_benchmark" => decisions.values.select { |row| row.fetch("final_verdict") == "invalid" }
    .group_by { |row| row.fetch("benchmark") }.transform_values(&:size),
  "unresolved" => unresolved, "source_only" => true,
  "overlay_verdict_changes" => overlay_changes,
  "qt_review_policy" => qt_plan.fetch("policy"),
  "retained_qt_sol_reviews" => qt_plan.fetch("retained_results").size,
  "policy" => "Compose the same-source primary, all-backend QT, explicitly approved fixed-size-setup policy, and targeted cross-review decisions. Every original conflict is retained and resolved explicitly; this integrity report introduces no scientific verdict."
}
output = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation/audit-completion-review.json"
raise "Audit completion report already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.dirname(output))
puts JSON.pretty_generate(report)
