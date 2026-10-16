require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

root = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "lib/claude_generation_observation")
id = "qtclustering_claude-sonnet-5.5-cc-medium_omp_r2"
source = File.join(manifest.fetch("workspace"), id)
incident = File.join(root, "incidents", "20261015-oom")
raise "Incident already captured" if File.exist?(incident)
raise "Canonical observation already exists" if File.exist?(File.join(manifest.fetch("persistent_results"), id))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is not idle" unless status.exitstatus == 1 && pids.empty?
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
reports = Dir[File.join(root, "observations", "*.json")].sort.to_h do |path|
  report = JSON.parse(File.read(path))
  directory = File.join(manifest.fetch("persistent_results"), report.fetch("id"))
  current = ClaudeGenerationObservation.read(directory, model: manifest.fetch("invoked_model"),
    version: manifest.fetch("claude_version"), baseline: baseline)
  raise "Completed observation changed: #{report.fetch('id')}" unless current == report
  [report.fetch("id"), { "report_sha256" => Digest::SHA256.file(path).hexdigest,
    "metadata_sha256" => report.fetch("sha256") }]
end
raise "Completed scope differs" unless reports.size == 50
paths = Dir[File.join(source, "**", "*")].select { |path| File.file?(path) }.sort
relative = paths.map { |path| path.delete_prefix(source + "/") }
expected = %w[common/hash.hpp common/results_output.hpp output.txt qtclustering/CMakeLists.txt qtclustering/qtclustering.cpp].sort
raise "Unexpected unfinished-observation files: #{relative.inspect}" unless relative == expected
events = File.foreach(File.join(source, "output.txt")).filter_map { |line| JSON.parse(line) rescue nil }
results = events.select { |event| event["type"] == "result" }
raise "Ambiguous final result" unless results.size == 1 && events.last == results.first
result = results.first
raise "Agent did not complete normally" unless result["subtype"] == "success" && result["is_error"] == false && result["terminal_reason"] == "completed"
raise "Unexpected model usage" unless result.fetch("modelUsage").keys == [manifest.fetch("invoked_model")]
properties, error, status = Open3.capture3("systemctl", "--user", "show", manifest.fetch("generation_unit"),
  "-p", "Result", "-p", "ExecMainStatus", "-p", "ExecMainCode", "-p", "ExecMainStartTimestamp",
  "-p", "ExecMainExitTimestamp", "-p", "ActiveState", "-p", "SubState", "-p", "MemoryPeak",
  "-p", "MemoryMax", "-p", "MemoryHigh", "-p", "OOMPolicy", "-p", "OOMScoreAdjust")
raise error unless status.success?
service = properties.lines.to_h { |line| line.strip.split("=", 2) }
raise "Unexpected controller outcome" unless service["Result"] == "oom-kill" && service["ActiveState"] == "failed"
journal, error, status = Open3.capture3("journalctl", "--user", "--utc", "-u", manifest.fetch("generation_unit"),
  "--since", "2026-10-15 00:05:50 UTC", "--until", "2026-10-15 00:06:10 UTC", "--no-pager", "-o", "short-iso")
raise error unless status.success?
FileUtils.mkdir_p(incident)
FileUtils.cp_r(source, File.join(incident, "original-workspace"), preserve: true)
digests = paths.to_h do |path|
  name = path.delete_prefix(source + "/")
  original = Digest::SHA256.file(path).hexdigest
  raise "Preservation copy differs" unless Digest::SHA256.file(File.join(incident, "original-workspace", name)).hexdigest == original
  [name, { "sha256" => original, "bytes" => File.size(path), "mtime" => File.mtime(path).utc.iso8601(6) }]
end
File.write(File.join(incident, "service-properties.txt"), properties)
File.write(File.join(incident, "service-journal.txt"), journal)
record = {
  "schema_version" => 1, "captured_at" => Time.now.utc.iso8601, "campaign_id" => manifest.fetch("campaign_id"),
  "state" => "awaiting_recovery_policy_decision", "run_id" => id, "service" => service,
  "completed_observations_verified" => reports, "preserved_workspace" => source, "workspace_files" => digests,
  "agent_terminal_result" => result.reject { |key, _| key == "result" },
  "missing_wrapper_metadata" => %w[instruction.txt timing.txt process-status.txt usage.txt],
  "kernel_victim_identity" => "Not accessible with current journal privileges; no privileged changes made.",
  "cause_evidence" => "An interim generated version did not remove a selected candidate, causing unbounded member growth. The agent later fixed this within the same invocation. The service recorded an OOM event and roughly 990 GiB peak memory; OOMPolicy=stop terminated the petert controller, but its llmtest child continued and emitted a successful final result.",
  "timing_evidence" => { "claude_duration_ms" => result.fetch("duration_ms"), "api_duration_ms" => result.fetch("duration_api_ms"),
    "wrapper_wall_time" => "unavailable", "agent_exit_status" => "unavailable", "controller_exit_signal" => service.fetch("ExecMainStatus").to_i,
    "transcript_mtime" => File.mtime(File.join(source, "output.txt")).utc.iso8601(6) },
  "recommendation" => "Retain the completed original program without regeneration; explicitly label recovered native CLI wall duration and unavailable external exit status. Set OOMPolicy=continue on the campaign supervisor without changing resource limits, then resume the remaining 169 observations after approval.",
  "no_programs_rerun" => true, "no_generated_sources_modified" => true, "account_verified_idle" => true
}
File.write(File.join(incident, "incident.json"), JSON.pretty_generate(record) + "\n")
FileUtils.cp(__FILE__, File.join(incident, "capture-oom-incident.rb"))
File.write(File.join(root, "STOP"), "Hold after controller OOM: retain the completed QT-clustering OpenMP r2 workspace; awaiting recovery-policy decision. See incidents/20261015-oom/incident.json. Do not regenerate this ID.\n")
puts JSON.pretty_generate({ "incident" => incident, "completed_verified" => reports.size, "original_files_preserved" => digests.size,
  "native_duration_seconds" => result.fetch("duration_ms") / 1000.0, "stop_guard" => true })
