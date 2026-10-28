# frozen_string_literal: true

require "/tmp/haiku55-opencode-evaluation-20261028.7dGRMp/experiment/tools/timing_audit/lib/timing_audit"
primary = "/home/petert/llm_timing_audit/20261028-haiku55-opencode"
campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
policy_path = File.join(campaign, "review-policy.json")
policy = JSON.parse(File.read(policy_path))
raise "Wrong review policy" unless policy.fetch("policy") == "luna_first_uncertainty_or_disagreement_v1"
policy.fetch("retained_results").each do |path, digest|
  raise "Completed pilot evidence changed" unless TimingAudit.sha256_file(path) == digest
end
qt_plan_path = File.join(primary + "-qtclustering-sol61", "adjudication-plan-full.json")
qt_plan = JSON.parse(File.read(qt_plan_path))
raise "QT selection uses obsolete policy" unless qt_plan.fetch("policy") == policy.fetch("policy")
models = {
  primary => ["gpt-5.6-luna", "high"],
  "#{primary}-priority" => ["gpt-5.6-luna", "high"],
  "#{primary}-sol61" => ["gpt-6.1-sol", "xhigh"],
  "#{primary}-qtclustering" => ["gpt-5.6-luna", "high"],
  "#{primary}-qtclustering-sol61" => ["gpt-6.1-sol", "xhigh"]
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
[primary, "#{primary}-qtclustering"].each do |root|
  path = File.join(root, "final/decisions.jsonl")
  inputs[path] = TimingAudit.sha256_file(path)
  TimingAudit.load_jsonl(path).each do |row|
    id = row.fetch("program_id")
    digest = row.fetch("source_digest")
    raise "Overlay source mismatch for #{id}" if source_digests.key?(id) && source_digests.fetch(id) != digest
    if decisions[id] && decisions.fetch(id).fetch("final_verdict") != row.fetch("final_verdict")
      overlay_changes << { "program_id" => id, "primary_verdict" => decisions.fetch(id).fetch("final_verdict"),
        "boundary_verdict" => row.fetch("final_verdict"), "boundary_basis" => row.fetch("decision_basis"),
        "primary_categories" => decisions.fetch(id).fetch("final_issue_categories"),
        "boundary_categories" => row.fetch("final_issue_categories") }
    end
    source_digests[id] = digest
    decisions[id] = row
  end
end
require "/tmp/haiku55-opencode-evaluation-20261028.7dGRMp/experiment/lib/local_evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261028-haiku55-opencode-validation"
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
report = {
  "checked_at" => TimingAudit.utc_now, "passed" => unresolved.empty?,
  "unique_programs" => decisions.size, "reviews" => reports, "input_sha256" => inputs,
  "verdicts" => decisions.values.map { |row| row.fetch("final_verdict") }.tally,
  "corrections_by_benchmark" => decisions.values.select { |row| row.fetch("final_verdict") == "invalid" }
    .group_by { |row| row.fetch("benchmark") }.transform_values(&:size),
  "unresolved" => unresolved, "source_only" => true,
  "overlay_verdict_changes" => overlay_changes,
  "qt_review_policy" => qt_plan.fetch("policy"),
  "retained_qt_sol_reviews" => qt_plan.fetch("retained_results").size,
  "policy" => "Reconcile the same-source all-backend QT overlay; retain all original review evidence; no new scientific verdicts in this integrity report."
}
output = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation/audit-completion-review.json"
raise "Audit completion report already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.dirname(output))
puts JSON.pretty_generate(report)
