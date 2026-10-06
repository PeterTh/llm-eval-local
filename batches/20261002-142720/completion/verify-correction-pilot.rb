# frozen_string_literal: true

require "/tmp/opus55-evaluation-20261006.cnIZzu/audit-tools/tools/timing_audit/lib/timing_fix"
require "/tmp/opus55-evaluation-20261006.cnIZzu/audit-tools/tools/timing_audit/lib/timing_fix_review"
require "/tmp/opus55-evaluation-20261006.cnIZzu/audit-tools/tools/timing_audit/lib/timing_fix_adjudication"

proposals = "/home/petert/llm_timing_fixes/20261006-opus55-proposals"
review = "/home/petert/llm_timing_fixes/20261006-opus55-review-pilot"
adjudication = "/home/petert/llm_timing_fixes/20261006-opus55-review-pilot-sol61"
TimingFix::ProposalVerifier.new(proposals, "trial").run
TimingFixReview::Verifier.new(review, "full").run
TimingFixAdjudication::Verifier.new(adjudication, "full").run
ids = File.readlines(File.join(proposals, "trial-ids.txt"), chomp: true).reject(&:empty?).sort
reviews = TimingAudit.load_jsonl(File.join(review, "summary-full.jsonl"))
adjudications = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl"))
raise "Pilot coverage mismatch" unless ids.size == 16 && ids == reviews.map { |row| row.fetch("program_id") }.sort
raise "Pilot requires further adjudication inspection" unless adjudications.empty?
raise "Pilot has unresolved reviews" unless reviews.all? { |row| row.fetch("verdict") == "accept" && row.fetch("confidence") == "high" }
compiled = YAML.safe_load_file(File.join(proposals, "materialized/summary-trial.yaml"))
raise "Pilot compilation failed" unless compiled.fetch("compile_successes") == ids.size && compiled.fetch("compile_failures").empty?

[[proposals, "proposals", "gpt-6.1-sol"], [review, "results", "gpt-5.6-luna"]].each do |root, response_dir, model|
  ids.each do |id|
    response_sha = TimingAudit.sha256_file(File.join(root, response_dir, "#{id}.json"))
    metadata = Dir[File.join(root, "logs", id, "attempt-*/metadata.yaml")].map { |path| YAML.safe_load_file(path) }
    accepted = metadata.select { |row| row["result_sha256"] == response_sha || row["proposal_sha256"] == response_sha }
    raise "No bound response for #{id}" if accepted.empty?
    raise "Pilot reviewer identity mismatch for #{id}" unless accepted.all? { |row|
      row.fetch("model") == model && row.fetch("reasoning_effort") == "high" && row.fetch("static_only_verified") == true
    }
  end
end
paths = [
  File.join(proposals, "manifest.yaml"), File.join(proposals, "inventory.jsonl"),
  File.join(proposals, "trial-ids.txt"), File.join(proposals, "summary-trial.jsonl"),
  File.join(proposals, "materialized/summary-trial.yaml"), File.join(proposals, "materialized/timing-fixes-trial.patch"),
  File.join(review, "manifest.yaml"), File.join(review, "summary-full.jsonl"),
  File.join(adjudication, "manifest.yaml"), File.join(adjudication, "summary-full.jsonl")
]
report = {
  "checked_at" => TimingAudit.utc_now, "passed" => true, "records" => ids.size,
  "compile_successes" => ids.size, "independent_acceptances" => ids.size,
  "unresolved_ids" => [], "review_root" => review, "adjudication_root" => adjudication,
  "source_only_evidence_verified" => true,
  "input_sha256" => paths.to_h { |path| [path, TimingAudit.sha256_file(path)] },
  "policy" => "Every pilot proposal compiled and independently satisfied both timing validity and timing-only scope at high confidence; expand with exact pilot evidence reuse."
}
output = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium/evaluation/correction-pilot-gate.json"
raise "Pilot gate already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
