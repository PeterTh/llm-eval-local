# frozen_string_literal: true

require "/tmp/fable51-evaluation-20261107-sdN1oM/experiment/tools/timing_audit/lib/timing_audit"
primary = "/home/petert/llm_timing_audit/20261107-fable51-medium"
campaign = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation"
policy_path = File.join(campaign, "review-policy.json")
policy = JSON.parse(File.read(policy_path))
require_relative 'audit-citation-normalization'
normalization_summary_path = File.join(campaign, 'audit-citation-normalization.json')
normalization_summary = JSON.parse(File.read(normalization_summary_path))
normalization_receipt = normalization_summary.fetch('receipt')
raise 'Normalization receipt changed' unless TimingAudit.sha256_file(normalization_receipt) == normalization_summary.fetch('receipt_sha256')
AuditCitationNormalization.verify!(normalization_receipt)
normalization = JSON.parse(File.read(normalization_receipt))
normalization.fetch('prior_accepted_results_sha256').each do |path, digest|
  raise 'Pre-normalization accepted review changed' unless TimingAudit.sha256_file(path) == digest
end
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
platform_inputs = {}
platform_reconciliation = nil
if File.directory?(primary + '-platform-sol61')
  receipt = File.join(campaign, 'platform-timing-reconciliation.json')
  platform_reconciliation = JSON.parse(File.read(receipt))
  proof_path = File.join(campaign, 'cholesky-mpi-r2-topology-context/preprocessing-proof.json')
  proof = JSON.parse(File.read(proof_path))
  platform_root = primary + '-platform-sol61'
  raise 'Platform follow-up manifest changed' unless TimingAudit.sha256_file(File.join(platform_root, 'manifest.yaml')) == platform_reconciliation.fetch('manifest_sha256')
  raise 'Platform preprocessing proof changed' unless TimingAudit.sha256_file(proof_path) == platform_reconciliation.fetch('preprocessing_proof_sha256') &&
    TimingAudit.sha256_file(File.join(platform_root, 'platform-context.txt')) == proof.fetch('context_sha256')
  before_path = File.join(primary, 'final-before-platform-reconciliation/decisions.jsonl')
  after_path = File.join(primary, 'final/decisions.jsonl')
  raise 'Platform finalization proof changed' unless TimingAudit.sha256_file(before_path) == platform_reconciliation.fetch('prior_final_decisions_sha256') &&
    TimingAudit.sha256_file(after_path) == platform_reconciliation.fetch('resolved_final_decisions_sha256')
  before = TimingAudit.load_jsonl(before_path).to_h { |row| [row.fetch('program_id'), row] }
  after = TimingAudit.load_jsonl(after_path).to_h { |row| [row.fetch('program_id'), row] }
  selected = platform_reconciliation.fetch('program_ids')
  raise 'Platform follow-up changed unrelated decisions' unless before.reject { |id, _| selected.include?(id) } == after.reject { |id, _| selected.include?(id) }
  platform_reconciliation.fetch('cases').each do |row|
    id = row.fetch('program_id')
    prior = File.join(primary + '-sol61', 'results', id + '.json')
    followup = File.join(platform_root, 'results', id + '.json')
    raise 'Platform response changed' unless TimingAudit.sha256_file(prior) == row.fetch('original_review_sha256') &&
      TimingAudit.sha256_file(followup) == row.fetch('followup_response_sha256')
  end
  models[platform_root] = ['gpt-6.1-sol', 'xhigh']
  platform_inputs = [receipt, proof_path, before_path, File.join(platform_root, 'supplemental-selection.jsonl')]
    .to_h { |path| [path, TimingAudit.sha256_file(path)] }
end
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
inputs.merge!(platform_inputs)
inputs.merge!([normalization_summary_path, normalization_receipt, File.join(__dir__, 'audit-citation-normalization.rb')].to_h { |path| [path, TimingAudit.sha256_file(path)] })
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
require "/tmp/fable51-evaluation-20261107-sdN1oM/experiment/lib/local_evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261107-fable51-medium-validation"
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
  "checked_at" => TimingAudit.utc_now, "passed" => unresolved.empty? && overlay_changes.empty?,
  "unique_programs" => decisions.size, "reviews" => reports, "input_sha256" => inputs,
  "decision_roots" => [primary, "#{primary}-qtclustering"],
  "platform_reconciliation" => platform_reconciliation,
  "syntax_normalized_response" => { "program_id" => normalization.fetch('program_id'),
    "receipt_sha256" => TimingAudit.sha256_file(normalization_receipt),
    "raw_response_preserved" => true, "scientific_verdict_or_claim_changed" => false },
  "verdicts" => decisions.values.map { |row| row.fetch("final_verdict") }.tally,
  "corrections_by_benchmark" => decisions.values.select { |row| row.fetch("final_verdict") == "invalid" }
    .group_by { |row| row.fetch("benchmark") }.transform_values(&:size),
  "unresolved" => unresolved, "source_only" => true,
  "overlay_verdict_changes" => overlay_changes,
  "qt_review_policy" => qt_plan.fetch("policy"),
  "retained_qt_sol_reviews" => qt_plan.fetch("retained_results").size,
  "policy" => "Reconcile the same-source all-backend QT overlay; differing verdicts require explicit resolution before corrections. Retain all original reviews; this integrity report introduces no scientific verdict."
}
output = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation/audit-completion-review.json"
raise "Audit completion report already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.dirname(output))
puts JSON.pretty_generate(report)
