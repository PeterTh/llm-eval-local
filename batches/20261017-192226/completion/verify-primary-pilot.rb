# frozen_string_literal: true

require "/tmp/sol61-opencode-evaluation-20261018.bNo4yq/experiment/tools/timing_audit/lib/timing_audit"
root = "/home/petert/llm_timing_audit/20261018-sol61-opencode"
campaign = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium/evaluation"
TimingAudit::AuditVerifier.new(root, "trial").run
ids = File.readlines(File.join(root, "trial-ids.txt"), chomp: true)
rows = ids.map { |id| JSON.parse(File.read(File.join(root, "results", "#{id}.json"))) }
raise "Unexpected pilot selection" unless ids.size == 16 && rows.map { |r| r.fetch("program_id") }.sort == ids.sort
types = Hash.new(0)
events = ids.flat_map { |id| Dir[File.join(root, "logs", id, "attempt-*", "events.jsonl")] }
events.each do |path|
  File.foreach(path) do |line|
    item = JSON.parse(line)["item"]
    next unless item
    types[item.fetch("type")] += 1
    raise "Prohibited tool event" unless %w[agent_message reasoning error].include?(item.fetch("type"))
  end
end
rows.each do |row|
  result_path = File.join(root, "results", "#{row.fetch('program_id')}.json")
  accepted = Dir[File.join(root, "logs", row.fetch("program_id"), "attempt-*", "metadata.yaml")].filter_map do |path|
    data = YAML.safe_load_file(path)
    data if data["result_sha256"] == TimingAudit.sha256_file(result_path)
  end
  raise "Unbound or wrong-model response" unless !accepted.empty? && accepted.all? { |data|
    data["model"] == "gpt-5.6-luna" && data["reasoning_effort"] == "high" && data["static_only_verified"] == true
  }
end
report = {
  "schema_version" => 1, "reviewed_at" => TimingAudit.utc_now, "passed" => true,
  "scope" => "Operational/usability gate for the primary pilot; independent scientific review remains mandatory",
  "model" => "gpt-5.6-luna", "effort" => "high", "workers" => 4,
  "results" => rows.size, "retained_attempts" => events.size,
  "empty_attempts" => events.count { |path| File.zero?(path) },
  "reviewer_attempts" => events.count { |path| !File.zero?(path) },
  "verdict_counts" => rows.map { |r| r.fetch("verdict") }.tally,
  "confidence_counts" => rows.map { |r| r.fetch("confidence") }.tally,
  "schema_source_hash_and_event_verification" => "passed", "agent_tool_calls" => 0,
  "event_item_types" => types,
  "gate_checks" => [
    "Each response is bound to the original source, schema and requested reviewer identity, with nonempty in-range source citations.",
    "No tool executions occurred in any retained attempt.",
    "Verdicts remain provisional until the required independent review and uncertainty-only adjudication.",
    "The separate QT boundary audit supersedes overlapping decisions at the same original revision before any correction."
  ],
  "decision" => "Expand only after the QT pilot also passes. Independently review invalid, ambiguous, non-high-confidence and valid-without-explicit-MPI_MAX cases; use blind Sol-6.1/xhigh for disagreements and uncertainty.",
  "source_commit" => "352c09d57e14ef93744aa8cc741ff52884079e5f",
  "inventory_sha256" => TimingAudit.sha256_file(File.join(root, "inventory.jsonl")),
  "trial_ids_sha256" => TimingAudit.sha256_file(File.join(root, "trial-ids.txt")),
  "primary_manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml"))
}
path = File.join(root, "pilot-review.json")
raise "Pilot review already exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
