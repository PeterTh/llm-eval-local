# frozen_string_literal: true
$stdout.sync = true
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix"
require_relative "verified-external-validation"

campaign = BeamExternalValidation::CAMPAIGN
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
overlay = primary + "-replicated-work-final-20261101"
old_proposals = "/home/petert/llm_timing_fixes/20261030-beam10-opencode-proposals"
proposals = old_proposals + "-reconciled-20261101"
resolution_path = File.join(campaign, "replicated-work-correction-selection-20261101.json")
report_path = File.join(campaign, "audit-completion-replicated-work-review.json")
raise "Reconciliation already exists" if [overlay, proposals, resolution_path, report_path].any? { |path| File.exist?(path) }
external = BeamExternalValidation.verify!
old_report_path = File.join(campaign, "audit-completion-supplemental-review.json")
old_report = JSON.parse(File.read(old_report_path))
raise "Previous audit did not pass" unless old_report.fetch("passed") && old_report.fetch("unresolved").empty?
inputs = old_report.fetch("input_sha256").merge(external.fetch(:paths))
inputs[old_report_path] = TimingAudit.sha256_file(old_report_path)
inputs.each { |path, sha| raise "Prior evidence changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
authorization_path = File.join(campaign, "replicated-work-user-decision-20261101.json")
authorization = JSON.parse(File.read(authorization_path))
policy_path = File.join(campaign, "replicated-work-timing-contract-20261101.txt")
raise "User policy changed" unless TimingAudit.sha256_file(policy_path) == authorization.fetch("policy_sha256")
inputs[authorization_path] = TimingAudit.sha256_file(authorization_path)
inputs[policy_path] = TimingAudit.sha256_file(policy_path)
inputs[__FILE__] = TimingAudit.sha256_file(__FILE__)
old_hold = File.join(campaign, "correction-build-scope-review-20261101.json")
JSON.parse(File.read(old_hold)).fetch("proposal_sha256").each do |name, sha|
  path = File.join(old_proposals, "proposals", name)
  raise "Retained proposal changed: #{name}" unless TimingAudit.sha256_file(path) == sha
  inputs[path] = sha
end
inputs[old_hold] = TimingAudit.sha256_file(old_hold)

models = {
  primary + "-replicated-work-luna-20261101" => ["gpt-5.6-luna", "high", 5],
  primary + "-replicated-work-extra-luna-20261101" => ["gpt-5.6-luna", "high", 4],
  primary + "-replicated-work-sol61-20261101" => ["gpt-6.1-sol", "xhigh", 1]
}
selected = {}
review_reports = models.map do |root, (model, effort, count)|
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: model, effort: effort)
  verifier = TimingAudit::AuditVerifier.new(root, "full")
  inventory = TimingAudit.load_jsonl(File.join(root, "inventory.jsonl"))
  paths = Dir[File.join(root, "results/*.json")].sort
  raise "Incomplete focused review: #{root}" unless inventory.size == count && paths.size == count
  paths.each do |path|
    response = JSON.parse(File.read(path))
    id = response.fetch("program_id")
    verifier.verify_result!(id, response)
    accepted = Dir[File.join(root, "logs", id, "attempt-*/metadata.yaml")].filter_map do |metadata_path|
      metadata = YAML.safe_load_file(metadata_path)
      metadata if metadata["result_sha256"] == TimingAudit.sha256_file(path)
    end
    raise "Unbound model review: #{id}" if accepted.empty?
    raise "Wrong focused model/effort: #{id}" unless accepted.all? { |row| row.values_at("model", "reasoning_effort", "static_only_verified") == [model, effort, true] }
    inputs[path] = TimingAudit.sha256_file(path)
    selected[id] = { "root" => root, "model" => model, "effort" => effort, "response" => response, "response_sha256" => inputs.fetch(path) }
  end
  events = Dir[File.join(root, "logs/**/events.jsonl")]
  events.each { |path| TimingAudit.verify_static_events!(path) }
  manifest = File.join(root, "manifest.yaml")
  inputs[manifest] = TimingAudit.sha256_file(manifest)
  { "root" => root, "model" => model, "effort" => effort, "responses" => paths.size,
    "retained_attempts" => events.size, "nonempty_event_streams" => events.count { |path| !File.zero?(path) },
    "prohibited_tool_events" => 0, "manifest_sha256" => inputs.fetch(manifest) }
end
unresolved = selected.select { |_id, entry| entry.fetch("response").values_at("verdict", "confidence") != ["valid", "high"] }
raise "Focused review needs adjudication: #{unresolved.keys.join(', ')}" unless unresolved.empty?
raise "Unexpected consistency coverage" unless selected.size == 9 && !selected.key?(authorization.fetch("explicit_case"))

effective = {}
[primary, primary + "-qtclustering"].each do |root|
  TimingAudit.load_jsonl(File.join(root, "final/decisions.jsonl")).each { |row| effective[row.fetch("program_id")] = row }
end
raise "Audit coverage changed" unless effective.size == 88
all_ids = (selected.keys + [authorization.fetch("explicit_case")]).sort
prior_decisions = all_ids.map { |id| effective.fetch(id) }
raise "Unexpected prior verdict" unless prior_decisions.all? { |row| row.fetch("final_verdict") == "invalid" }
TimingAudit.derive_inventory(parent_root: primary, output_dir: overlay, ids: all_ids, provenance: {
  "decision_overlay" => { "kind" => "user_complete_result_contract_and_focused_static_reviews",
    "authorization_sha256" => inputs.fetch(authorization_path), "operator_decisions" => 1, "model_reviewed_decisions" => selected.size,
    "policy" => "Same-source additive decisions; prior results and proposals are preserved, not edited." }
})
records = TimingAudit.load_jsonl(File.join(overlay, "inventory.jsonl")).to_h { |row| [row.fetch("id"), row] }
source = YAML.safe_load_file(File.join(overlay, "manifest.yaml")).fetch("generated_source")
raise "Source commit changed" unless source.fetch("commit") == authorization.fetch("source_commit")
repository = TimingAudit::SourceRepository.new(root: File.join(__dir__, "generated"), commit: source.fetch("commit"))
decisions = all_ids.map do |id|
  record = records.fetch(id)
  repository.dossier(record)
  previous = effective.fetch(id)
  raise "Reviewed source changed: #{id}" unless previous.fetch("source_digest") == record.fetch("source_digest")
  details = if selected.key?(id)
    entry = selected.fetch(id)
    response = entry.fetch("response")
    { "decision_basis" => entry.fetch("model") == "gpt-6.1-sol" ? "user_replica_contract_and_focused_sol_adjudication" : "user_replica_contract_and_focused_luna_review",
      "semantic_equivalence_basis" => response.fetch("semantic_equivalence_basis"), "notes" => response.fetch("notes"),
      "evidence" => response.fetch("evidence"), "replicated_work_review" => entry.except("response") }
  else
    raise "User decision source mismatch" unless record.fetch("source_digest") == authorization.fetch("source_digest")
    { "decision_basis" => "user_complete_result_replica_adjudication",
      "semantic_equivalence_basis" => "Each process owns full nx*ny*nz arrays and independently executes every iteration over the complete grid. The local timer encloses both complete OpenMP update loops and their implicit thread completion. No rank contributes data needed for another process's complete answer; a maximum across redundant copies is not required.",
      "notes" => "Explicit user adjudication; not a model review. Preserve the original OpenMP-only source and build configuration. No source edit, MPI linkage or backend-compliance repair is required.",
      "evidence" => [
        { "path" => "cahn-hilliard/cahn_hilliard.cpp", "lines" => "184-214", "finding" => "Each process allocates full arrays and locally times all complete-grid iterations before reporting elapsed milliseconds." },
        { "path" => "cahn-hilliard/cahn_hilliard.cpp", "lines" => "38-73", "finding" => "Both update functions cover every x/y/z cell and finish their OpenMP parallel-for constructs before returning." }
      ] }
  end
  decision = previous.merge(details).merge("final_verdict" => "valid", "final_confidence" => "high", "final_issue_categories" => ["none"],
    "timing_fix_required" => false, "timing_review_required" => false, "timing_only_fix_possible" => false, "minimal_fix" => "",
    "superseded_final_verdict" => previous.fetch("final_verdict"), "superseded_decision_basis" => previous.fetch("decision_basis"),
    "user_authorization_sha256" => inputs.fetch(authorization_path), "replicated_work_policy_sha256" => authorization.fetch("policy_sha256"))
  effective[id] = decision
  decision
end
final = File.join(overlay, "final")
TimingAudit.atomic_write(File.join(final, "decisions.jsonl"), TimingAudit.dump_jsonl(decisions))
TimingAudit.atomic_write(File.join(final, "prior-decisions.jsonl"), TimingAudit.dump_jsonl(prior_decisions))
TimingAudit.atomic_write(File.join(final, "correction-ids.txt"), "")
TimingAudit.atomic_write(File.join(final, "review-ids.txt"), "")
TimingAudit.atomic_write(File.join(final, "finalizer-snapshot.rb"), File.binread(__FILE__))
TimingAudit.atomic_write(File.join(overlay, "user-decision.json"), File.binread(authorization_path))
TimingAudit.atomic_write(File.join(overlay, "replicated-work-timing-contract.txt"), File.binread(policy_path))
metadata = { "created_at" => TimingAudit.utc_now, "records" => decisions.size, "final_verdict_counts" => { "valid" => decisions.size },
  "roots" => { "primary" => primary, "priority_review" => nil, "adjudication" => nil },
  "focused_review_roots" => models.keys, "operator_adjudications" => 1, "model_reviewed_decisions" => selected.size,
  "decisions_sha256" => TimingAudit.sha256_file(File.join(final, "decisions.jsonl")),
  "finalizer_sha256" => TimingAudit.sha256_file(__FILE__), "input_sha256" => inputs,
  "policy" => "Source-pinned user criterion plus nine targeted model investigations (one disagreement adjudicated by Sol); no model result is fabricated for the user's explicit case." }
TimingAudit.atomic_write(File.join(final, "metadata.yaml"), YAML.dump(metadata))
%w[manifest.yaml inventory.jsonl final/metadata.yaml final/decisions.jsonl].each do |name|
  path = File.join(overlay, name)
  inputs[path] = TimingAudit.sha256_file(path)
end
invalid_ids = effective.select { |_id, row| row.fetch("final_verdict") == "invalid" }.keys.sort
correction_ids = invalid_ids - external.fetch(:excluded)
raise "Unexpected correction reconciliation" unless correction_ids.size == 46 && (all_ids & correction_ids).empty?
report = old_report.merge("checked_at" => TimingAudit.utc_now, "prior_report" => old_report_path,
  "reviews" => old_report.fetch("reviews") + review_reports, "input_sha256" => inputs,
  "verdicts" => effective.values.map { |row| row.fetch("final_verdict") }.tally,
  "corrections_by_benchmark" => effective.values.select { |row| row.fetch("final_verdict") == "invalid" }.group_by { |row| row.fetch("benchmark") }.transform_values(&:size),
  "operator_adjudications" => 1, "replicated_work_accepted_ids" => all_ids,
  "effective_correction_ids" => correction_ids, "excluded_external_validation_ids" => external.fetch(:excluded),
  "policy" => "Preserve prior audit evidence; apply the user-approved complete-result replica criterion consistently with source-only focused reviews. Distributed-computation timing requirements and native execution settings remain unchanged.")
TimingAudit.atomic_write(report_path, JSON.pretty_generate(report) + "\n")
inputs = inputs.merge(report_path => TimingAudit.sha256_file(report_path))
TimingFix::InventoryBuilder.new(audit_root: primary, overlay_roots: [primary + "-qtclustering", overlay],
  output_dir: proposals, source_root: File.join(__dir__, "generated"), trial_size: 16,
  context_path: File.join(old_proposals, "platform-context.txt"), validation_exclusions: BeamExternalValidation::REGISTRY).run
inventory_path = File.join(proposals, "inventory.jsonl")
raise "Prepared correction subset differs" unless TimingAudit.load_jsonl(inventory_path).map { |row| row.fetch("id") }.sort == correction_ids
%w[proposal review].each do |kind|
  original = "/home/petert/llm_eval/experiment/tools/timing_audit/bin/timing_fix_#{kind}_reuse.rb"
  dependency = kind == "proposal" ? "timing_fix" : "timing_fix_review"
  body = File.read(original)
  marker = "require_relative \"../lib/#{dependency}\""
  raise "Reuse dependency marker changed" unless body.scan(marker).size == 1
  adapted = body.sub(marker, "require #{File.join(__dir__, "experiment-supplemental/tools/timing_audit/lib", dependency).inspect}")
  destination = File.join(__dir__, "timing-fix-#{kind}-reuse-frozen.rb")
  TimingAudit.atomic_write(destination, adapted)
  FileUtils.cp(destination, campaign)
  inputs[original] = TimingAudit.sha256_file(original)
  inputs[destination] = TimingAudit.sha256_file(destination)
end
require_relative "timing-fix-proposal-reuse-frozen"
reuse = TimingFixProposalReuse.run(source: old_proposals, destination: proposals, model: "gpt-6.1-sol", effort: "high")
%w[manifest.yaml inventory.jsonl reused-proposals.json].each do |name|
  path = File.join(proposals, name)
  inputs[path] = TimingAudit.sha256_file(path)
end
pilot = "/home/petert/llm_timing_fixes/20261030-beam10-opencode-review-pilot"
reuse_ids = TimingAudit.load_jsonl(File.join(pilot, "inventory.jsonl")).map { |row| row.fetch("id") }.sort & correction_ids
resolution = { "created_at" => TimingAudit.utc_now, "passed" => true,
  "source_commit" => source.fetch("commit"), "overlay_root" => overlay, "proposal_root" => proposals,
  "input_sha256" => inputs, "correction_ids" => correction_ids, "corrections" => correction_ids.size,
  "accepted_unchanged_replica_ids" => all_ids, "external_validation_excluded_ids" => external.fetch(:excluded),
  "benchmark_eligible_ids" => external.fetch(:eligible_ids), "benchmark_eligible" => external.fetch(:eligible_ids).size,
  "pilot_review_reuse_ids" => reuse_ids, "reused_proposals" => reuse.fetch("records").size, "new_proposal_requests" => 0,
  "new_independent_correction_reviews" => correction_ids.size - reuse_ids.size,
  "prior_proposal_root" => old_proposals, "prior_proposals_preserved" => true,
  "source_edits_applied" => false, "program_executions" => 0 }
TimingAudit.atomic_write(resolution_path, JSON.pretty_generate(resolution) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(resolution.except("input_sha256", "correction_ids", "benchmark_eligible_ids"))
