# frozen_string_literal: true

require "/tmp/opus55-evaluation-20261006.cnIZzu/audit-tools/tools/timing_audit/lib/timing_audit"

primary = "/home/petert/llm_timing_audit/20261006-opus55"
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
    "attempts" => events.size, "prohibited_tool_events" => 0,
    "manifest_sha256" => TimingAudit.sha256_file(File.join(root, "manifest.yaml")) }
end

decisions = {}
source_digests = {}
inputs = {}
[primary, "#{primary}-qtclustering"].each do |root|
  path = File.join(root, "final/decisions.jsonl")
  inputs[path] = TimingAudit.sha256_file(path)
  TimingAudit.load_jsonl(path).each do |row|
    id = row.fetch("program_id")
    digest = row.fetch("source_digest")
    raise "Overlay source mismatch for #{id}" if source_digests.key?(id) && source_digests.fetch(id) != digest
    source_digests[id] = digest
    decisions[id] = row
  end
end
raise "Combined audit coverage changed" unless decisions.size == 119
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
  "policy" => "Reconcile the same-source all-backend QT overlay; retain all original review evidence; no new scientific verdicts in this integrity report."
}
output = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium/evaluation/audit-completion-review.json"
raise "Audit completion report already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
