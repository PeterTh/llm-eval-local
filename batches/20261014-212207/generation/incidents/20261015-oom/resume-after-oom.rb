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
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
runtime = manifest.fetch("runtime_root")
incident_root = File.join(root, "incidents/20261015-oom")
source = "/home/petert/llm_eval/experiment"
receipt_path = File.join(root, "resume-20261015.json")
raise "Resume already recorded" if File.exist?(receipt_path) || File.exist?(File.join(root, "supervision.json"))
raise "STOP guard absent" unless File.file?(File.join(root, "STOP"))
raise "Account busy" unless GenerationCleanup.new.pids.empty?
recovery = JSON.parse(File.read(File.join(incident_root, "recovery.json")))
raise "Recovery not ready" unless recovery.fetch("completed") == 51 && recovery.fetch("unstarted") == 169 && recovery.fetch("source_and_transcript_unchanged")
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true)
completed = Dir.children(manifest.fetch("persistent_results"))
raise "Completed scope differs" unless completed.size == 51 && (completed - ids).empty?
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
campaign = GenerationCampaign.new(root)
completed.each { |id| campaign.observation(id, baseline: baseline) }
fable = manifest.fetch("paused_campaign").fetch("path")
raise "Fable STOP guard absent" unless File.file?(File.join(fable, "STOP"))
raise "Fable pause receipt changed" unless Digest::SHA256.file(File.join(fable, "operator-pause.json")).hexdigest == manifest.fetch("paused_campaign").fetch("pause_receipt_sha256")
fable_manifest = JSON.parse(File.read(File.join(fable, "campaign.json")))
%w[generation_unit monitor_timer].each do |key|
  raise "Fable active" if %w[active activating].include?(properties(fable_manifest.fetch(key), ["ActiveState"]).fetch("ActiveState"))
end
manifest.fetch("files").each do |relative, digest|
  raise "Generation harness changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == digest
end
manifest.fetch("benchmark_files").each do |relative, digest|
  raise "Sequential input changed: #{relative}" unless Digest::SHA256.file(File.join(runtime, "benchmarks", relative)).hexdigest == digest
end
raise "CLI changed" unless Digest::SHA256.file(manifest.fetch("claude_binary")).hexdigest == manifest.fetch("claude_binary_sha256")

commit = checked("git", "-C", source, "rev-parse", "HEAD").strip
raise "Wrong recovery revision" unless commit.start_with?("8164d46")
raise "Tooling not backed up upstream" unless commit == checked("git", "-C", source, "rev-parse", "origin/codex").strip
files = %w[tools/generation_campaign.rb lib/claude_generation_observation.rb lib/claude_generation_recovery.rb
  lib/codex_generation_observation.rb lib/codex_usage.rb lib/generation_cleanup.rb lib/experiment_selection.rb]
runtime_copy = File.join(runtime, "supervisor-#{commit[0, 7]}")
persistent_copy = File.join(root, "supervision-#{commit[0, 7]}")
raise "Supervisor destination already exists" if File.exist?(runtime_copy) || File.exist?(persistent_copy)
digests = files.to_h do |relative|
  bytes = checked("git", "-C", source, "show", "#{commit}:#{relative}")
  raise "Uncommitted supervisor change: #{relative}" unless bytes == File.binread(File.join(source, relative))
  [runtime_copy, persistent_copy].each do |base|
    target = File.join(base, relative)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(source, relative), target)
    File.chmod(0444, target)
  end
  [relative, Digest::SHA256.hexdigest(bytes)]
end
test_log = File.join(runtime, "recovery-regression-tests.log")
raise "Regression tests not clean" unless File.read(test_log).include?("232 runs, 1412 assertions, 0 failures, 0 errors, 0 skips")
FileUtils.cp(test_log, File.join(incident_root, File.basename(test_log)))
%w[supervisor-run.rb resume-after-oom.rb].each { |name| FileUtils.cp(File.join(runtime, name), File.join(incident_root, name)) }
revision = { "deployed_at" => Time.now.utc.iso8601, "source_commit" => commit,
  "generation_source_commit" => manifest.fetch("source_commit"), "generation_snapshot_unchanged" => true,
  "campaign_manifest_sha256" => Digest::SHA256.file(File.join(root, "campaign.json")).hexdigest,
  "generation_launcher_sha256" => Digest::SHA256.file(File.join(runtime, "run.rb")).hexdigest,
  "supervisor_launcher_sha256" => Digest::SHA256.file(File.join(runtime, "supervisor-run.rb")).hexdigest,
  "files" => digests, "runtime_copy" => runtime_copy, "persistent_copy" => persistent_copy,
  "regression_tests_sha256" => Digest::SHA256.file(test_log).hexdigest,
  "generation_unit" => manifest.fetch("generation_unit"), "oom_policy" => "continue",
  "policy" => "User-approved completed-session recovery only; unchanged generation harness, CLI, prompt, budget, resource limits and input code. Existing successful observations are not regenerated." }

generation_unit = manifest.fetch("generation_unit")
resource_fields = %w[MemoryHigh MemoryMax MemorySwapMax CPUQuotaPerSecUSec CPUWeight AllowedCPUs EffectiveCPUs TasksMax LimitNOFILE OOMScoreAdjust KillMode]
before = properties(generation_unit, resource_fields + %w[OOMPolicy ActiveState Result InvocationID ExecMainCode ExecMainStatus])
raise "Unexpected old service state" unless before.fetch("ActiveState") == "failed" && before.fetch("Result") == "oom-kill" && before.fetch("OOMPolicy") == "stop"
File.write(File.join(incident_root, "pre-resume-service-properties.json"), JSON.pretty_generate(before) + "\n")
File.write(File.join(root, "supervision.json"), JSON.pretty_generate(revision) + "\n")
checked("systemctl", "--user", "reset-failed", generation_unit)
raise "Failed transient service not released" unless properties(generation_unit, ["LoadState"]).fetch("LoadState") == "not-found"
%w[monitor_unit monitor_timer].each do |key|
  raise "Old monitor is still loaded" unless properties(manifest.fetch(key), ["LoadState"]).fetch("LoadState") == "not-found"
end
raise "Account became busy" unless GenerationCleanup.new.pids.empty?
FileUtils.mv(File.join(root, "STOP"), File.join(incident_root, "STOP-before-resume"))
command = ["systemd-run", "--user", "--unit=#{generation_unit}",
  "--description=Sonnet 5.5 medium production campaign (resume unstarted observations)",
  "--property=Type=exec", "--property=OOMPolicy=continue", "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--property=StandardOutput=append:#{root}/generation.log", "--property=StandardError=append:#{root}/generation.log",
  "/usr/bin/ruby", File.join(runtime, "supervisor-run.rb")]
begin
  puts checked(*command)
rescue StandardError
  FileUtils.cp(File.join(incident_root, "STOP-before-resume"), File.join(root, "STOP"))
  raise
end
after = properties(generation_unit, resource_fields + %w[OOMPolicy ActiveState InvocationID ExecMainStartTimestamp])
raise "Resume service not active" unless after.fetch("ActiveState") == "active" && after.fetch("OOMPolicy") == "continue"
raise "Resource limits changed" unless before.slice(*resource_fields) == after.slice(*resource_fields)
puts checked("systemd-run", "--user", "--unit=#{manifest.fetch('monitor_unit')}",
  "--description=Four-hour Sonnet 5.5 campaign status", "--on-active=4h", "--on-unit-active=4h",
  "--timer-property=AccuracySec=1min", "--property=Type=oneshot",
  "--property=StandardOutput=append:#{root}/monitor.log", "--property=StandardError=append:#{root}/monitor.log",
  "/usr/bin/ruby", File.join(runtime, "monitor.rb"))
receipt = { "resumed_at" => Time.now.utc.iso8601, "completed_reused" => 51, "unstarted" => 169,
  "next_id" => (ids - completed).first, "command" => command, "original_service" => before, "resumed_service" => after,
  "resource_properties_unchanged" => true, "supervision" => revision,
  "monitor_timer" => properties(manifest.fetch("monitor_timer"), %w[ActiveState NextElapseUSecMonotonic TimersMonotonic]),
  "monitor_timer_definition" => checked("systemctl", "--user", "cat", manifest.fetch("monitor_timer")),
  "stopped_guard_preserved" => "incidents/20261015-oom/STOP-before-resume" }
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
puts JSON.generate({ "resumed" => generation_unit, "invocation" => after.fetch("InvocationID"), "oom_policy" => after.fetch("OOMPolicy"),
  "resource_limits_unchanged" => true, "completed_reused" => 51, "unstarted" => 169, "receipt" => receipt_path })
