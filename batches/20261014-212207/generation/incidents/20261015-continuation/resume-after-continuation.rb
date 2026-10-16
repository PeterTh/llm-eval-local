require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require "/home/petert/llm_eval/experiment/tools/generation_campaign"

def checked(*command)
  output, error, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{error}" unless status.success?
  output
end

def properties(unit, names)
  checked("systemctl", "--user", "show", unit, *names.flat_map { |name| ["-p", name] }).lines.to_h { |line| line.strip.split("=", 2) }
end

root = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium"
manifest_path = File.join(root, "campaign.json")
manifest = JSON.parse(File.read(manifest_path))
runtime = manifest.fetch("runtime_root")
source = "/home/petert/llm_eval/experiment"
incident_root = File.join(root, "incidents/20261015-continuation")
raise "Continuation incident already recorded" if File.exist?(incident_root)
raise "Account busy" unless GenerationCleanup.new.pids.empty?
raise "Unexpected operator STOP" if File.exist?(File.join(root, "STOP"))
id = "qtclustering_claude-sonnet-5.5-cc-medium_cuda_r2"
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true)
completed = Dir.children(manifest.fetch("persistent_results"))
raise "Completed scope differs" unless completed.sort == ids.take(62).sort
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
reports = completed.to_h do |run_id|
  report = ClaudeGenerationObservation.read(File.join(manifest.fetch("persistent_results"), run_id), model: manifest.fetch("invoked_model"),
    version: manifest.fetch("claude_version"), baseline: baseline, batch: manifest.fetch("campaign_id"))
  path = File.join(root, "observations", "#{run_id}.json")
  if run_id == id
    raise "Rejected observation already accepted" if File.exist?(path)
  else
    raise "Previously accepted observation changed: #{run_id}" unless JSON.parse(File.read(path)) == report
  end
  [run_id, report]
end
report = reports.fetch(id)
raise "Native accounting changed" unless report.fetch("total_seconds") == 886.54 && report.fetch("api_seconds") == 182.908 && report.fetch("total_tokens") == 493606 && report.fetch("retry_count").zero?
fable = manifest.fetch("paused_campaign").fetch("path")
raise "Fable STOP guard absent" unless File.file?(File.join(fable, "STOP"))
fable_manifest = JSON.parse(File.read(File.join(fable, "campaign.json")))
%w[generation_unit monitor_timer].each do |key|
  raise "Fable active" if %w[active activating].include?(properties(fable_manifest.fetch(key), ["ActiveState"]).fetch("ActiveState"))
end
manifest.fetch("files").each do |relative, digest|
  raise "Frozen harness changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == digest
end
manifest.fetch("benchmark_files").each do |relative, digest|
  raise "Frozen input changed: #{relative}" unless Digest::SHA256.file(File.join(runtime, "benchmarks", relative)).hexdigest == digest
end
raise "CLI changed" unless Digest::SHA256.file(manifest.fetch("claude_binary")).hexdigest == manifest.fetch("claude_binary_sha256")
commit = checked("git", "-C", source, "rev-parse", "HEAD").strip
raise "Wrong parser revision" unless commit.start_with?("3f380f9")
raise "Revision not backed up" unless commit == checked("git", "-C", source, "rev-parse", "origin/codex").strip
test_log = File.join(runtime, "continuation-regression-tests.log")
raise "Tests did not pass" unless File.read(test_log).include?("236 runs, 1431 assertions, 0 failures, 0 errors, 0 skips")
generation_unit = manifest.fetch("generation_unit")
resource_fields = %w[OOMPolicy MemoryHigh MemoryMax MemorySwapMax CPUQuotaPerSecUSec CPUWeight AllowedCPUs EffectiveCPUs TasksMax LimitNOFILE OOMScoreAdjust KillMode]
before = properties(generation_unit, resource_fields + %w[ActiveState Result InvocationID ExecMainStatus])
raise "Unexpected service state" unless before.fetch("ActiveState") == "failed" && before.fetch("Result") == "exit-code" && before.fetch("OOMPolicy") == "continue"
%w[monitor_unit monitor_timer].each do |key|
  raise "Old monitor loaded" unless properties(manifest.fetch(key), ["LoadState"]).fetch("LoadState") == "not-found"
end

FileUtils.mkdir_p(incident_root)
File.write(File.join(root, "STOP"), "Hold while deploying the tested same-session continuation parser correction.\n")
%w[progress.json monitor-status.json FOLLOWUP.md].each { |name| FileUtils.cp(File.join(root, name), File.join(incident_root, name)) }
File.write(File.join(incident_root, "service-properties.json"), JSON.pretty_generate(before) + "\n")
File.write(File.join(incident_root, "service-journal.txt"), checked("journalctl", "--user", "-u", generation_unit, "--no-pager", "--since", "2026-10-15 09:37:00"))
FileUtils.cp(test_log, File.join(incident_root, File.basename(test_log)))
%w[resume-after-continuation.rb revision-supervisor-run.rb].each { |name| FileUtils.cp(File.join(runtime, name), File.join(incident_root, name)) }

previous_revision = JSON.parse(File.read(File.join(root, "supervision.json")))
runtime_copy = File.join(runtime, "supervisor-#{commit[0, 7]}")
persistent_copy = File.join(root, "supervision-#{commit[0, 7]}")
raise "New supervisor already exists" if File.exist?(runtime_copy) || File.exist?(persistent_copy)
digests = previous_revision.fetch("files").keys.to_h do |relative|
  bytes = checked("git", "-C", source, "show", "#{commit}:#{relative}")
  raise "Uncommitted supervisor change" unless bytes == File.binread(File.join(source, relative))
  [runtime_copy, persistent_copy].each do |base|
    target = File.join(base, relative)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(source, relative), target)
    File.chmod(0444, target)
  end
  [relative, Digest::SHA256.hexdigest(bytes)]
end
revision = previous_revision.merge("deployed_at" => Time.now.utc.iso8601, "source_commit" => commit, "campaign_root" => root,
  "files" => digests, "runtime_copy" => runtime_copy, "persistent_copy" => persistent_copy,
  "supervisor_launcher_sha256" => Digest::SHA256.file(File.join(runtime, "revision-supervisor-run.rb")).hexdigest,
  "regression_tests_sha256" => Digest::SHA256.file(test_log).hexdigest,
  "policy" => "Accept same-session task-notification continuations queued before the preceding result only when origin matches an observed notification; allow current directory changes only inside the original workspace. Identity/capability and cumulative accounting checks remain enforced. No generation settings or results are changed.")
revision_path = File.join(persistent_copy, "revision.json")
File.write(revision_path, JSON.pretty_generate(revision) + "\n")
canonical = File.join(manifest.fetch("persistent_results"), id)
events = File.readlines(File.join(canonical, "output.txt")).filter_map { |line| JSON.parse(line) rescue nil }
initializations = events.select { |event| event["type"] == "system" && event["subtype"] == "init" }
File.write(File.join(incident_root, "incident.json"), JSON.pretty_generate({ "captured_at" => Time.now.utc.iso8601,
  "run_id" => id, "classification" => "metadata_parser_false_positive", "generation_repeated" => false,
  "source_or_metadata_changed" => false, "previous_observations_verified_unchanged" => 61,
  "initialization_changes" => initializations.drop(1).map { |event| (event.keys | initializations.first.keys).select { |key| event[key] != initializations.first[key] } },
  "native_result_origins" => events.select { |event| event["type"] == "result" }.map { |event| event.slice("session_id", "origin", "duration_api_ms", "modelUsage") },
  "canonical_file_sha256" => Dir[File.join(canonical, "**/*")].select { |path| File.file?(path) && !File.symlink?(path) }.to_h { |path| [path.delete_prefix(canonical + "/"), Digest::SHA256.file(path).hexdigest] },
  "accepted_observation" => report, "supervision_revision" => revision_path }) + "\n")
GenerationCampaign.new(root).observation(id, baseline: baseline)
checked("systemctl", "--user", "reset-failed", generation_unit)
raise "Transient unit not released" unless properties(generation_unit, ["LoadState"]).fetch("LoadState") == "not-found"
raise "Account became busy" unless GenerationCleanup.new.pids.empty?
FileUtils.mv(File.join(root, "STOP"), File.join(incident_root, "STOP-before-resume"))
command = ["systemd-run", "--user", "--unit=#{generation_unit}", "--description=Sonnet 5.5 medium production campaign (same-session parser correction)",
  "--property=Type=exec", "--property=OOMPolicy=continue", "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--property=StandardOutput=append:#{root}/generation.log", "--property=StandardError=append:#{root}/generation.log",
  "/usr/bin/ruby", File.join(runtime, "revision-supervisor-run.rb"), revision_path]
begin
  puts checked(*command)
rescue StandardError
  FileUtils.cp(File.join(incident_root, "STOP-before-resume"), File.join(root, "STOP"))
  raise
end
after = properties(generation_unit, resource_fields + %w[ActiveState InvocationID ExecMainStartTimestamp])
raise "Resource limits changed" unless before.slice(*resource_fields) == after.slice(*resource_fields)
raise "Service not active" unless after.fetch("ActiveState") == "active"
puts checked("systemd-run", "--user", "--unit=#{manifest.fetch('monitor_unit')}",
  "--description=Four-hour Sonnet 5.5 campaign status", "--on-active=4h", "--on-unit-active=4h",
  "--timer-property=AccuracySec=1min", "--property=Type=oneshot",
  "--property=StandardOutput=append:#{root}/monitor.log", "--property=StandardError=append:#{root}/monitor.log",
  "/usr/bin/ruby", File.join(runtime, "monitor.rb"))
receipt = { "resumed_at" => Time.now.utc.iso8601, "completed_reused" => 62, "unstarted" => 158,
  "next_id" => (ids - completed).first, "command" => command, "service" => after, "resource_properties_unchanged" => true,
  "revision" => revision_path, "timer_definition" => checked("systemctl", "--user", "cat", manifest.fetch("monitor_timer")) }
File.write(File.join(incident_root, "resume.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.generate(receipt.reject { |key, _| %w[command timer_definition service].include?(key) }.merge("invocation" => after.fetch("InvocationID")))
