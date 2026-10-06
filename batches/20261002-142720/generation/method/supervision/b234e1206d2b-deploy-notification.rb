require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

root = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium"
runtime = "/tmp/opus55-generation.Lx4eWo"
source = "/home/petert/llm_eval/experiment"
commit = "a3eeeb276f3adab395387324c09a957e8c4b3d3b"
previous_commit = "5fd05f01581a0b483aed324b070601d18132cb5b"
revision = File.join(root, "supervision-revisions", commit)
raise "Revision already exists" if File.exist?(revision)
require File.join(source, "lib/generation_cleanup")
require File.join(source, "lib/claude_generation_observation")
raise "llmtest is busy" unless GenerationCleanup.new.pids.empty?
state, status = Open3.capture2("systemctl", "--user", "show", "llm-opus55-generation-20261002-142720.service", "--value", "-p", "ActiveState")
raise "Generation service is not stopped" unless status.success? && %w[failed inactive].include?(state.strip)
head, status = Open3.capture2("git", "-C", source, "rev-parse", "HEAD")
raise "Unexpected source commit" unless status.success? && head.strip == commit
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
previous = JSON.parse(File.read(File.join(root, "supervision-revisions", previous_commit, "amendment.json")))
manifest.fetch("files").each do |path, digest|
  raise "Frozen generation script changed: #{path}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), path)).hexdigest == digest
end
previous.fetch("files").each do |path, digest|
  raise "Unexpected runtime supervisor: #{path}" unless Digest::SHA256.file(File.join(runtime, "supervisor", path)).hexdigest == digest
end
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
reports = Dir[File.join(root, "observations", "*.json")].map { |path| JSON.parse(File.read(path)) }
raise "Unexpected accepted count" unless reports.size == 193
reports.each do |report|
  refreshed = ClaudeGenerationObservation.read(File.join(manifest.fetch("persistent_results"), report.fetch("id")),
    model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"), baseline: baseline)
  raise "Completed report changed: #{report.fetch('id')}" unless refreshed == report
end
affected = "qtclustering_claude-opus-5.5-cc-medium_cuda_r5"
accepted = ClaudeGenerationObservation.read(File.join(manifest.fetch("persistent_results"), affected),
  model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"), baseline: baseline)
files = previous.fetch("files").keys
FileUtils.mkdir_p(revision)
%w[progress.json monitor-status.json].each { |name| FileUtils.cp(File.join(root, name), File.join(revision, "before-#{name}")) }
files.each do |path|
  persistent = File.join(revision, path)
  target = File.join(runtime, "supervisor", path)
  FileUtils.mkdir_p(File.dirname(persistent))
  FileUtils.cp(File.join(source, path), persistent)
  File.chmod(0444, persistent)
  next if Digest::SHA256.file(target).hexdigest == Digest::SHA256.file(persistent).hexdigest
  File.chmod(0644, target)
  FileUtils.cp(persistent, target)
  File.chmod(0444, target)
end
FileUtils.cp(__FILE__, File.join(revision, "deploy-notification.rb"))
FileUtils.cp(File.join(runtime, "FOLLOWUP.md"), File.join(root, "FOLLOWUP.md"))
record = { "deployed_at" => Time.now.utc.iso8601, "source_commit" => commit,
  "supersedes_source_commit" => previous_commit, "existing_reports_unchanged" => reports.size,
  "generation_snapshot_unchanged" => true, "affected_id" => affected, "accepted_report" => accepted,
  "evidence" => { "init_lines" => [1, 1615], "result_lines" => [1611, 1620], "init_differing_keys" => ["uuid"],
    "same_session_and_process_socket" => true, "notification_line" => 1614,
    "followup_origin" => { "kind" => "task-notification", "producer" => "session-task" },
    "native_aggregate_parser" => "All 8 timing/token/retry fields agree; no warnings." },
  "next_id" => "roomsim_claude-opus-5.5-cc-medium_cuda_r5", "ungenerated_count" => 26,
  "tests" => "60 tests, 338 assertions; all passed.",
  "files" => files.to_h { |path| [path, Digest::SHA256.file(File.join(revision, path)).hexdigest] },
  "policy" => "Accept only verified identical-init same-session task-notification continuations with cumulative counters. No source, transcript, prompt, budget, model or elapsed-time changes; no reruns." }
File.write(File.join(revision, "amendment.json"), JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record.reject { |key, _| key == "accepted_report" })
