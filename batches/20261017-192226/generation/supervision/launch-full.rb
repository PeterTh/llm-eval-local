require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

def checked(*command)
  output, error, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{error}" unless status.success?
  output
end

root = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
review = JSON.parse(File.read(File.join(root, "preflight-review.json")))
raise "Pilot review is not accepted" unless review["accepted"] == true && review["original_results_reused"] == true && review["ids"] == manifest.fetch("preflight_ids")
raise "Launch receipt already exists" if File.exist?(File.join(root, "launch.json"))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless status.exitstatus == 1 && pids.empty?
raise "Operator stop requested" if File.exist?(File.join(root, "STOP"))
fable = manifest.fetch("paused_campaign").fetch("path")
raise "Fable STOP guard absent" unless File.exist?(File.join(fable, "STOP"))
fable_manifest = JSON.parse(File.read(File.join(fable, "campaign.json")))
%w[generation_unit monitor_timer].each do |key|
  raise "Fable active" unless checked("systemctl", "--user", "show", fable_manifest.fetch(key), "-p", "ActiveState", "--value").strip == "inactive"
end
puts checked("systemd-run", "--user", "--unit=#{manifest.fetch('generation_unit')}",
  "--description=Sol 6.1 Medium OpenCode campaign (reuse four accepted pilots)", "--property=Type=exec",
  "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--property=StandardOutput=append:#{root}/generation.log", "--property=StandardError=append:#{root}/generation.log",
  "/usr/bin/ruby", File.join(manifest.fetch("working_directory"), "tools/generation_campaign.rb"), "run", root)
puts checked("systemd-run", "--user", "--unit=#{manifest.fetch('monitor_unit')}",
  "--description=Four-hour Sol 6.1 OpenCode campaign status", "--on-active=4h", "--on-unit-active=4h",
  "--timer-property=AccuracySec=1min", "--property=Type=oneshot",
  "--property=StandardOutput=append:#{root}/monitor.log", "--property=StandardError=append:#{root}/monitor.log",
  "/usr/bin/ruby", File.join(manifest.fetch("runtime_root"), "monitor.rb"))
destination = File.join(root, "launch-full.rb")
FileUtils.cp(__FILE__, destination) unless File.expand_path(__FILE__) == File.expand_path(destination)
File.write(File.join(root, "launch.json"), JSON.pretty_generate({
  "launched_at" => Time.now.utc.iso8601, "expected_runs" => manifest.fetch("expected_runs"),
  "reused_pilot_ids" => review.fetch("ids"), "generation_unit" => manifest.fetch("generation_unit"),
  "monitor_timer" => manifest.fetch("monitor_timer"), "launch_script_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "monitor_note" => "The timer records local status and stops on completion/anomaly; active assistant supervision checks the records separately." }) + "\n")
puts File.read(File.join(root, "launch.json"))
