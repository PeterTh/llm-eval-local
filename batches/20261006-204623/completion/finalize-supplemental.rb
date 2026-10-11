# frozen_string_literal: true

require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_audit"
root = "/home/petert/llm_timing_audit/20261010-sol61-mpi-split-supplemental"
parent = "/home/petert/llm_timing_audit/20261010-sol61-qtclustering"
id = "qtclustering_gpt-6.1-sol-medium_hybrid_r2"
manifest = YAML.safe_load_file(File.join(root, "manifest.yaml"))
raise "Supplemental parent changed" unless manifest.dig("supplemental_adjudication", "parent_manifest_sha256") == TimingAudit.sha256_file(File.join(parent, "manifest.yaml"))
inventory = TimingAudit.load_jsonl(File.join(root, "inventory.jsonl"))
raise "Wrong supplemental selection" unless inventory.map { |r| r.fetch("id") } == [id]
TimingAudit::AuditVerifier.new(root, "full").run
result_path = File.join(root, "results", "#{id}.json")
result = JSON.parse(File.read(result_path))
raise "Supplemental review remains uncertain" if result.fetch("verdict") == "ambiguous" || result.fetch("confidence") != "high"
accepted = Dir[File.join(root, "logs", id, "attempt-*/metadata.yaml")].map { |path| YAML.safe_load_file(path) }
  .select { |row| row["result_sha256"] == TimingAudit.sha256_file(result_path) }
raise "Supplemental reviewer identity mismatch" unless !accepted.empty? && accepted.all? { |row|
  row.fetch("model") == "gpt-6.1-sol" && row.fetch("reasoning_effort") == "xhigh" && row.fetch("static_only_verified")
}
prior_path = File.join(parent, "final/decisions.jsonl")
prior = TimingAudit.load_jsonl(prior_path).find { |row| row.fetch("program_id") == id }
raise "Supplemental source mismatch" unless prior &&
  prior.fetch("source_digest") == inventory.first.fetch("source_digest") &&
  prior.fetch("source_tree_oid") == inventory.first.fetch("source_tree_oid")
decision = prior.merge(
  "supplemental_verdict" => result.fetch("verdict"), "final_verdict" => result.fetch("verdict"),
  "final_confidence" => result.fetch("confidence"), "final_issue_categories" => result.fetch("issue_categories"),
  "decision_basis" => "sol_6_1_blind_supplemental_adjudication_with_verified_mpi_implementation",
  "timing_fix_required" => result.fetch("verdict") == "invalid", "timing_review_required" => false,
  "timing_only_fix_possible" => result.fetch("timing_only_fix_possible"), "minimal_fix" => result.fetch("minimal_fix"),
  "timed_region" => result.fetch("timed_region"), "semantic_equivalence_basis" => result.fetch("semantic_equivalence_basis"),
  "notes" => result.fetch("notes"), "evidence" => result.fetch("evidence"),
  "prior_final_verdict" => prior.fetch("final_verdict"), "prior_final_confidence" => prior.fetch("final_confidence")
)
final = File.join(root, "final")
raise "Supplemental decisions already exist" if File.exist?(final)
TimingAudit.atomic_write(File.join(final, "decisions.jsonl"), TimingAudit.dump_jsonl([decision]))
TimingAudit.atomic_write(File.join(final, "correction-ids.txt"), decision.fetch("timing_fix_required") ? "#{id}\n" : "")
TimingAudit.atomic_write(File.join(final, "review-ids.txt"), "")
metadata = {
  "created_at" => TimingAudit.utc_now, "records" => 1,
  "final_verdict_counts" => { decision.fetch("final_verdict") => 1 },
  "roots" => { "primary" => parent, "priority_review" => nil, "adjudication" => "#{parent}-sol61", "supplemental_adjudication" => root },
  "parent_decisions_sha256" => TimingAudit.sha256_file(prior_path),
  "manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml")),
  "response_sha256" => TimingAudit.sha256_file(result_path),
  "decisions_sha256" => TimingAudit.sha256_file(File.join(final, "decisions.jsonl")),
  "finalizer_sha256" => TimingAudit.sha256_file(__FILE__),
  "review_model" => "gpt-6.1-sol", "review_effort" => "xhigh",
  "policy" => "Later same-source focused audit supersedes only this one record. Copy the fresh independent review verdict without a manual scientific override; preserve all earlier decisions and evidence.",
  "generated_program_executions" => 0
}
TimingAudit.atomic_write(File.join(final, "metadata.yaml"), YAML.dump(metadata))
TimingAudit.atomic_write(File.join(final, "finalizer-snapshot.rb"), File.binread(__FILE__))
puts JSON.pretty_generate(decision.slice("program_id", "final_verdict", "final_confidence", "timing_fix_required", "notes"))
