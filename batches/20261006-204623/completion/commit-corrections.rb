# frozen_string_literal: true

require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_fix"
require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_fix_review"
require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_fix_adjudication"
require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/lib/timing_fix_finalize"

proposals = "/home/petert/llm_timing_fixes/20261010-sol61-proposals"
review = "/home/petert/llm_timing_fixes/20261010-sol61-review"
adjudication = "/home/petert/llm_timing_fixes/20261010-sol61-review-sol61"
source = "/tmp/sol61-evaluation-20261010.xL0RJx/corrected"
original_commit = "6adaf64dc195651e5b3da3575738874e09fdc72d"
output = "/home/petert/llm_timing_fixes/20261010-sol61-final"
raise "Correction registry already exists" if File.exist?(output)
TimingAudit::SourceRepository.new(root: source, commit: original_commit)
TimingFix::ProposalVerifier.new(proposals, "full").run
TimingFixReview::Verifier.new(review, "full").run
TimingFixAdjudication::Verifier.new(adjudication, "full").run
records = TimingAudit.load_jsonl(File.join(review, "inventory.jsonl"))
expected_ids = TimingAudit.load_jsonl(File.join(proposals, "inventory.jsonl")).map { |row| row.fetch("id") }.sort
raise "Correction selection changed" unless records.map { |row| row.fetch("id") }.sort == expected_ids && !expected_ids.empty?
reviews = TimingAudit.load_jsonl(File.join(review, "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
adjudications = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
records.each do |record|
  id = record.fetch("id")
  result = adjudications[id] || reviews.fetch(id)
  verdict = result["final_verdict"] || result.fetch("verdict")
  raise "Unaccepted correction #{id}" unless verdict == "accept" && result.fetch("confidence") == "high"
end
compiled = YAML.safe_load_file(File.join(proposals, "materialized/summary-full.yaml"))
raise "Incomplete compile validation" unless compiled.fetch("compile_successes") == records.size && compiled.fetch("compile_failures").empty?
patch = File.join(proposals, "materialized/timing-fixes-full.patch")
raise "Compiled patch changed" unless TimingAudit.sha256_file(patch) == compiled.fetch("patch_sha256")
expected_paths = records.flat_map do |record|
  proposal = JSON.parse(File.read(File.join(proposals, "proposals", "#{record.fetch('id')}.json")))
  proposal.fetch("edits").map { |edit| File.join(record.fetch("source_prefix"), edit.fetch("path")) }
end.uniq.sort
raise "Correction paths escape this batch" unless expected_paths.all? { |path| path.start_with?("20261006-204623/") }
TimingAudit.capture!("git", "-C", source, "apply", "--check", patch)
TimingAudit.capture!("git", "-C", source, "apply", "--index", patch)
actual_paths = TimingAudit.capture!("git", "-C", source, "diff", "--cached", "--name-only", "--").lines(chomp: true).sort
raise "Staged path set differs from accepted proposals" unless actual_paths == expected_paths
records.each do |record|
  digest = TimingFixFinalize.verify_corrected_source!(source, record.fetch("source_prefix"), record)
  raise "Reviewed corrected source changed for #{record.fetch('id')}" unless digest == record.fetch("corrected_source_digest")
end
TimingAudit.capture!("git", "-C", source, "diff", "--cached", "--check")
TimingAudit.capture!("git", "-C", source, "commit", "-m", "Correct timing only for #{records.size} Sol 6.1 implementations")
corrected_commit = TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD").strip
raise "Correction commit has the wrong parent" unless TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD^").strip == original_commit
TimingFixFinalize.run(proposal_root: proposals, review_root: review, adjudication_root: adjudication,
  source_root: source, corrected_commit: corrected_commit, output_dir: output)
report = {
  "created_at" => TimingAudit.utc_now, "original_commit" => original_commit,
  "corrected_commit" => corrected_commit, "corrections" => records.size,
  "changed_paths" => actual_paths, "materialized_patch_sha256" => compiled.fetch("patch_sha256"),
  "registry_manifest_sha256" => TimingAudit.sha256_file(File.join(output, "manifest.yaml")),
  "source_root" => source, "pushed" => false, "revalidation_started" => false
}
TimingAudit.atomic_write("/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation/correction-commit.json",
  JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.slice("original_commit", "corrected_commit", "corrections", "source_root", "pushed"))
