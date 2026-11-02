# frozen_string_literal: true
$stdout.sync = true
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_materializer"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_review"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_adjudication"
require_relative "verified-replicated-work"
require_relative "timing-fix-proposal-reuse-frozen"
require_relative "timing-fix-review-reuse-frozen"
campaign = BeamExternalValidation::CAMPAIGN
prior = BeamReplicatedWork.verify!
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
focused = primary + "-replicated-broadcast-luna-20261101"
overlay = primary + "-replicated-broadcast-final-20261101"
id = "cahn-hilliard_beam-1.0-oc-medium_hybrid_r4"
prefix = "/home/petert/llm_timing_fixes/20261030-beam10-opencode"
proposals = prefix + "-proposals-final-selection-20261101"
review = prefix + "-review-final-selection-20261101"
adjudication = prefix + "-review-sol61-final-selection-20261101"
parent_review = prefix + "-review"
parent_adjudication = prefix + "-review-sol61"
report_path = File.join(campaign, "audit-completion-final-replica-review.json")
resolution_path = File.join(campaign, "final-replica-correction-selection-20261101.json")
raise "Final selection already exists" if [overlay, proposals, review, adjudication, report_path, resolution_path].any? { |path| File.exist?(path) }
completion = JSON.parse(File.read(File.join(campaign, "correction-resumed-progress-20261101.json")))
raise "Current correction reviews unresolved" unless completion.fetch("phase") == "awaiting_correction_commit_review" && completion.fetch("unresolved_ids").empty?
focused_progress = JSON.parse(File.read(File.join(campaign, "replicated-broadcast-review-progress-20261101.json")))
raise "Focused broadcast review incomplete" unless focused_progress.fetch("phase") == "awaiting_replicated_work_review"
TimingAudit::AuditRunner.new(output_dir: focused, scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high")
response_path = File.join(focused, "results", "#{id}.json")
response = JSON.parse(File.read(response_path))
TimingAudit::AuditVerifier.new(focused, "full").verify_result!(id, response)
raise "Broadcast case needs adjudication" unless response.values_at("verdict", "confidence") == ["valid", "high"]
attempts = Dir[File.join(focused, "logs", id, "attempt-*/metadata.yaml")]
accepted = attempts.map { |path| YAML.safe_load_file(path) }.select { |row| row["result_sha256"] == TimingAudit.sha256_file(response_path) }
raise "Focused model binding differs" unless !accepted.empty? && accepted.all? { |row| row.values_at("model", "reasoning_effort", "static_only_verified") == ["gpt-5.6-luna", "high", true] }
events = Dir[File.join(focused, "logs/**/events.jsonl")]
events.each { |path| TimingAudit.verify_static_events!(path) }
old_report_path = File.join(campaign, "audit-completion-replicated-work-review.json")
old_report = JSON.parse(File.read(old_report_path))
inputs = prior.fetch("input_sha256").dup
[__FILE__, old_report_path, response_path, File.join(focused, "manifest.yaml"), File.join(campaign, "replicated-broadcast-review-launch-20261101.json"),
  File.join(campaign, "replicated-work-correction-selection-20261101.json"), File.join(campaign, "correction-resumed-progress-20261101.json")].each { |path| inputs[path] = TimingAudit.sha256_file(path) }
effective = {}
roots = [primary, primary + "-qtclustering", prior.fetch("overlay_root")]
roots.each { |root| TimingAudit.load_jsonl(File.join(root, "final/decisions.jsonl")).each { |row| effective[row.fetch("program_id")] = row } }
previous = effective.fetch(id)
raise "Unexpected previous broadcast verdict" unless previous.fetch("final_verdict") == "invalid"
TimingAudit.derive_inventory(parent_root: primary, output_dir: overlay, ids: [id], provenance: {
  "decision_overlay" => { "kind" => "complete_result_input_broadcast_replica", "focused_review_root" => focused,
    "focused_manifest_sha256" => TimingAudit.sha256_file(File.join(focused, "manifest.yaml")), "parent_resolution_sha256" => TimingAudit.sha256_file(File.join(campaign, "replicated-work-correction-selection-20261101.json")) } })
record = TimingAudit.load_jsonl(File.join(overlay, "inventory.jsonl")).fetch(0)
raise "Focused source mismatch" unless record.fetch("source_digest") == previous.fetch("source_digest")
TimingAudit::SourceRepository.new(root: File.join(__dir__, "generated"), commit: prior.fetch("source_commit")).dossier(record)
decision = previous.merge("final_verdict" => "valid", "final_confidence" => "high", "final_issue_categories" => ["none"],
  "timing_fix_required" => false, "timing_review_required" => false, "timing_only_fix_possible" => false, "minimal_fix" => "",
  "decision_basis" => "user_replica_contract_and_focused_luna_review",
  "semantic_equivalence_basis" => response.fetch("semantic_equivalence_basis"), "notes" => response.fetch("notes"), "evidence" => response.fetch("evidence"),
  "superseded_final_verdict" => previous.fetch("final_verdict"), "superseded_decision_basis" => previous.fetch("decision_basis"),
  "replicated_work_review" => { "root" => focused, "model" => "gpt-5.6-luna", "effort" => "high", "response_sha256" => TimingAudit.sha256_file(response_path) })
effective[id] = decision
final = File.join(overlay, "final")
TimingAudit.atomic_write(File.join(final, "decisions.jsonl"), TimingAudit.dump_jsonl([decision]))
TimingAudit.atomic_write(File.join(final, "prior-decisions.jsonl"), TimingAudit.dump_jsonl([previous]))
TimingAudit.atomic_write(File.join(final, "correction-ids.txt"), "")
TimingAudit.atomic_write(File.join(final, "review-ids.txt"), "")
TimingAudit.atomic_write(File.join(final, "finalizer-snapshot.rb"), File.binread(__FILE__))
%w[user-decision.json replicated-work-timing-contract.txt].each { |name| TimingAudit.atomic_write(File.join(overlay, name), File.binread(File.join(prior.fetch("overlay_root"), name))) }
TimingAudit.atomic_write(File.join(final, "metadata.yaml"), YAML.dump({ "created_at" => TimingAudit.utc_now, "records" => 1,
  "roots" => { "primary" => primary, "priority_review" => nil, "adjudication" => nil }, "focused_review_roots" => [focused],
  "final_verdict_counts" => { "valid" => 1 }, "decisions_sha256" => TimingAudit.sha256_file(File.join(final, "decisions.jsonl")),
  "input_sha256" => inputs, "finalizer_sha256" => TimingAudit.sha256_file(__FILE__), "operator_adjudications" => 0,
  "policy" => "One additional same-source input-broadcast replica, independently reviewed under the existing user-approved complete-result criterion. Earlier evidence stays unchanged." }))
%w[manifest.yaml inventory.jsonl final/metadata.yaml final/decisions.jsonl].each { |name| path = File.join(overlay, name); inputs[path] = TimingAudit.sha256_file(path) }
ids = prior.fetch("correction_ids") - [id]
raise "Final selection differs unexpectedly" unless ids.size == 45 && effective.size == 88
all_replicas = (prior.fetch("accepted_unchanged_replica_ids") + [id]).sort
review_report = { "root" => focused, "model" => "gpt-5.6-luna", "effort" => "high", "responses" => 1,
  "retained_attempts" => events.size, "nonempty_event_streams" => events.count { |path| !File.zero?(path) },
  "prohibited_tool_events" => 0, "manifest_sha256" => TimingAudit.sha256_file(File.join(focused, "manifest.yaml")) }
report = old_report.merge("checked_at" => TimingAudit.utc_now, "prior_report" => old_report_path,
  "reviews" => old_report.fetch("reviews") + [review_report], "input_sha256" => inputs,
  "verdicts" => effective.values.map { |row| row.fetch("final_verdict") }.tally,
  "corrections_by_benchmark" => effective.values.select { |row| row.fetch("final_verdict") == "invalid" }.group_by { |row| row.fetch("benchmark") }.transform_values(&:size),
  "replicated_work_accepted_ids" => all_replicas, "effective_correction_ids" => ids)
TimingAudit.atomic_write(report_path, JSON.pretty_generate(report) + "\n")
inputs = inputs.merge(report_path => TimingAudit.sha256_file(report_path))
TimingFix::InventoryBuilder.new(audit_root: primary, overlay_roots: roots.drop(1) + [overlay], output_dir: proposals,
  source_root: File.join(__dir__, "generated"), trial_size: 16, context_path: File.join(prior.fetch("proposal_root"), "platform-context.txt"),
  validation_exclusions: BeamExternalValidation::REGISTRY).run
raise "Final proposal inventory differs" unless TimingAudit.load_jsonl(File.join(proposals, "inventory.jsonl")).map { |row| row.fetch("id") }.sort == ids
TimingFixProposalReuse.run(source: prior.fetch("proposal_root"), destination: proposals, model: "gpt-6.1-sol", effort: "high")
TimingFixMaterializer.run(output_dir: proposals, scope: "full", jobs: 4)
TimingFixReview::InventoryBuilder.new(proposal_root: proposals, output_dir: review, scope: "full").run
TimingFixReviewReuse.run(source: parent_review, destination: review, model: "gpt-5.6-luna", effort: "high", only_ids: ids)
TimingFixReview::Verifier.new(review, "full").run
TimingFixAdjudication::InventoryBuilder.new(review_root: review, output_dir: adjudication).run
adjudication_ids = TimingAudit.load_jsonl(File.join(adjudication, "inventory.jsonl")).map { |row| row.fetch("id") }.sort
unless adjudication_ids.empty?
  # Retain the exact historical compile-superset evidence used in the prior
  # adjudication prompt. Every selected corrected source is byte-identical.
  environment = File.join(parent_adjudication, "environment-evidence.yaml")
  old_environment = YAML.safe_load_file(environment)
  old_compile = YAML.safe_load_file(File.join(prior.fetch("proposal_root"), "materialized/summary-full.yaml"))
  raise "Original compile evidence changed" unless old_environment.fetch("compiled_patch") == old_compile.slice("records", "compile_successes", "compile_failures", "patch_sha256")
  new_environment = File.join(adjudication, "environment-evidence.yaml")
  TimingAudit.atomic_write(new_environment, File.binread(environment))
  manifest_path = File.join(adjudication, "manifest.yaml")
  manifest = YAML.safe_load_file(manifest_path)
  manifest.fetch("artifacts")["environment_evidence_sha256"] = TimingAudit.sha256_file(new_environment)
  manifest["compile_superset_evidence_reuse"] = { "parent_adjudication_root" => parent_adjudication,
    "parent_environment_sha256" => TimingAudit.sha256_file(environment), "parent_proposal_root" => prior.fetch("proposal_root"),
    "parent_compile_summary_sha256" => TimingAudit.sha256_file(File.join(prior.fetch("proposal_root"), "materialized/summary-full.yaml")),
    "policy" => "The retained original 46-program compile evidence includes every unchanged selected corrected source. This preserves the exact prior request; the separate final subset was also compiled." }
  TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
  body = File.read(File.join(__dir__, "timing-fix-review-reuse-frozen.rb"))
  body = body.gsub("TimingFixReviewReuse", "TimingFixAdjudicationReuse").gsub("TimingFixReview::", "TimingFixAdjudication::")
  body = body.sub('lib/timing_fix_review"', 'lib/timing_fix_adjudication"')
  helper = File.join(__dir__, "timing-fix-adjudication-reuse-frozen.rb")
  TimingAudit.atomic_write(helper, body)
  load helper
  TimingFixAdjudicationReuse.run(source: parent_adjudication, destination: adjudication, model: "gpt-6.1-sol", effort: "xhigh", only_ids: adjudication_ids)
  inputs[helper] = TimingAudit.sha256_file(helper)
  FileUtils.cp(helper, campaign)
end
TimingFixAdjudication::Verifier.new(adjudication, "full").run
reviews = TimingAudit.load_jsonl(File.join(review, "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
adjudications = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
raise "Final correction reviews unresolved" unless ids.all? { |key| row = adjudications[key] || reviews.fetch(key); (row["final_verdict"] || row["verdict"]) == "accept" && row.fetch("confidence") == "high" }
[proposals, review, adjudication].each do |root|
  Dir[File.join(root, "*.{yaml,json,jsonl,rb,txt}"), File.join(root, "materialized/summary-full.yaml")].sort.each { |path| inputs[path] = TimingAudit.sha256_file(path) if File.file?(path) }
end
resolution = prior.merge("created_at" => TimingAudit.utc_now, "input_sha256" => inputs,
  "overlay_roots" => [prior.fetch("overlay_root"), overlay], "proposal_root" => proposals,
  "review_root" => review, "adjudication_root" => adjudication, "corrections" => ids.size, "correction_ids" => ids,
  "accepted_unchanged_replica_ids" => all_replicas, "reused_proposals" => ids.size,
  "reused_complete_postfix_reviews" => ids.size, "reused_postfix_adjudications" => adjudication_ids.size,
  "new_independent_correction_reviews" => 0, "new_proposal_requests" => 0,
  "pilot_review_reuse_ids" => prior.fetch("pilot_review_reuse_ids") & ids,
  "prior_reconciled_proposal_root" => prior.fetch("proposal_root"), "all_corrections_compiled_and_accepted" => true,
  "policy" => "Final strict subset after one additional broadcast-replica check; no generation, validation or benchmark observations repeated, and no new correction model calls. All original decisions, proposals, compiled supersets and reviews remain retained.")
TimingAudit.atomic_write(resolution_path, JSON.pretty_generate(resolution) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(resolution.slice("created_at", "corrections", "benchmark_eligible", "reused_proposals", "reused_complete_postfix_reviews", "reused_postfix_adjudications", "new_proposal_requests", "accepted_unchanged_replica_ids"))
