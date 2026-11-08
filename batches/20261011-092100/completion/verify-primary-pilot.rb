# frozen_string_literal: true

require "/tmp/fable51-evaluation-20261107-sdN1oM/experiment/tools/timing_audit/lib/timing_audit"
root = "/home/petert/llm_timing_audit/20261107-fable51-medium"
campaign = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation"
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
  "primary_source_quality_check" => {
    "checked_at" => TimingAudit.utc_now,
    "samples" => {
      "black-scholes_claude-fable-5.1-cc-medium_mpi_r3" => "Checked source 201-227: partitioned options, barrier, complete local loop, MPI_DOUBLE/MPI_MAX and correct millisecond reporting match the review.",
      "matmul_claude-fable-5.1-cc-medium_mpi_r1" => "Checked source 186-207 and 218-240: row-distributed work, root-local timer after the start barrier and after Gatherv, no duration reduction. Semantic-equivalence judgment remains provisional for independent review.",
      "spmv_claude-fable-5.1-cc-medium_hybrid_r1" => "Checked source 438-483 and 499-525: partitioned rows, synchronized GPU completion, two barriers and root-local reporting without duration reduction. The missing_start_synchronization tag describes lack of a common-start proof, not literal absence of a barrier; do not add unrelated synchronization or alter computation based on that tag."
    },
    "qt_boundary_samples" => {
      "qtclustering_claude-fable-5.1-cc-medium_cuda_r1" => "Checked bound preprocessing 324-337, synchronized grow/result paths 360-425 and enclosing timer 551-568.",
      "qtclustering_claude-fable-5.1-cc-medium_omp_r3" => "Checked preprocessing within the parallel region 273-297 and enclosing timer 520-537.",
      "qtclustering_claude-fable-5.1-cc-medium_hybrid_r5" => "Checked coordinate-format uploads 1371-1422, synchronized kernel/results 1538-1554, algorithmic preprocessing 1561-1620 and local timer/reporting 1924-1939."
    },
    "decision" => "Usable source-grounded proposals. No scientific verdict is accepted by this operational pilot gate; required independent review and uncertainty/disagreement adjudication follow."
  },
  "gate_checks" => [
    "Each response is bound to the original source, schema and requested reviewer identity, with nonempty in-range source citations.",
    "No tool executions occurred in any retained attempt.",
    "Verdicts remain provisional until the required independent review and uncertainty-only adjudication.",
    "The separate QT boundary audit supersedes overlapping decisions at the same original revision before any correction."
  ],
  "decision" => "Expand only after the QT pilot also passes. Independently review invalid, ambiguous, non-high-confidence and valid-without-explicit-MPI_MAX cases; use blind Sol-6.1/xhigh for disagreements and uncertainty.",
  "source_commit" => "e3a476e84284ddea4052c6e55e92439f10f38b1a",
  "inventory_sha256" => TimingAudit.sha256_file(File.join(root, "inventory.jsonl")),
  "trial_ids_sha256" => TimingAudit.sha256_file(File.join(root, "trial-ids.txt")),
  "primary_manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml"))
}
path = File.join(root, "pilot-review.json")
raise "Pilot review already exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
