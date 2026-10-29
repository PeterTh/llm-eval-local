# frozen_string_literal: true
require "json"
require "open3"
require "digest"
require "fileutils"
require "time"

action = ARGV.fetch(0)
raise "Use preflight or run" unless %w[preflight run].include?(action)
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
runtime = manifest.fetch("runtime_root")
receipt_path = File.join(campaign, "#{action}-launch.json")
raise "Already launched; inspect before resuming" if File.exist?(receipt_path)
raise "Campaign stopped" if File.exist?(File.join(campaign, "STOP"))
haiku = JSON.parse(File.read("/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation/publication.json"))
raise "Haiku not verified" unless haiku.fetch("status") == "passed"
def checked(*args)
  output, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error}\n#{output}" unless status.success?
  output
end
raise "Wrong campaign" unless manifest.fetch("models") == {
  "gpt-6.1-terra-medium" => { "model" => "gpt-6.1-terra", "reasoning_effort" => "medium" } } &&
  manifest.fetch("expected_runs") == 220 && manifest.fetch("per_run_timeout_seconds") == 14400
manifest.fetch("files").each do |relative, sha|
  raise "Frozen method differs" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == sha
end
native = JSON.parse(File.read(File.join(campaign, "filesystem-preflight.json")))
raise "Wrong isolation evidence" unless native.fetch("inferences_launched").zero? && native.fetch("private_state_removed") && native.fetch("lifecycle_exit_status").zero?
raise "Published method differs" unless checked("git", "-C", "/home/petert/llm_eval/experiment", "ls-remote", "--exit-code", "origin", "refs/heads/codex").strip == "#{manifest.fetch('source_commit')}\trefs/heads/codex"
fable = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium"
raise "Fable is not suspended" unless File.file?(File.join(fable, "STOP"))
units = checked("systemctl", "--user", "list-units", "--type=service", "--state=active,activating", "--no-legend", "--no-pager", "llm-*")
active = units.lines.map { |line| line.strip.split.first }.reject { |name| name.include?("-monitor-") }
raise "Another campaign is active: #{active.inspect}" unless active.empty?
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "llmtest is busy" unless status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native host busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
if action == "run"
  gate = JSON.parse(File.read(File.join(campaign, "preflight-gate.json")))
  raise "Pilot not accepted" unless gate.fetch("accepted") && gate.fetch("preflights").map { |r| r.fetch("id") } == manifest.fetch("preflight_ids")
  review = JSON.parse(File.read(File.join(campaign, "preflight-review.json")))
  raise "Pilot not reviewed" unless review.fetch("passed") && review.fetch("retained_pilot_reexecuted") == false
else
  raise "Preflight already has observations" unless Dir[File.join(campaign, "observations", "*.json")].empty?
end
unit = manifest.fetch(action == "preflight" ? "preflight_unit" : "generation_unit")
lock.close
output = checked("systemd-run", "--user", "--unit=#{unit}", "--description=Terra 6.1 medium Codex #{action}",
  "--property=Type=exec", "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{campaign}/#{action}.log", "--property=StandardError=append:#{campaign}/#{action}.log",
  "/usr/bin/ruby", File.join(runtime, "controller.rb"), action)
receipt = { "launched_at" => Time.now.utc.iso8601, "action" => action, "unit" => unit,
  "campaign_id" => manifest.fetch("campaign_id"), "source_commit" => manifest.fetch("source_commit"),
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest, "systemd_output" => output }
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, File.join(campaign, "launch.rb"))
FileUtils.cp(__FILE__, File.join(runtime, "launch.rb")) unless File.expand_path(__FILE__) == File.join(runtime, "launch.rb")
if action == "run"
  monitor = manifest.fetch("monitor_unit").delete_suffix(".service")
  puts checked("systemd-run", "--user", "--unit=#{monitor}", "--description=Four-hour Terra generation status",
    "--on-active=4h", "--on-unit-active=4h", "--timer-property=AccuracySec=1min", "--property=Type=oneshot",
    "--property=StandardOutput=append:#{campaign}/monitor.log", "--property=StandardError=append:#{campaign}/monitor.log",
    "/usr/bin/ruby", File.join(runtime, "monitor.rb"))
end
puts JSON.pretty_generate(receipt)
