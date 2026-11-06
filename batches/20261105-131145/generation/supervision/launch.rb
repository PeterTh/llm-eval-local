# frozen_string_literal: true
require "json"
require "open3"
require "time"
require "digest"
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
raise "No additional launch arguments" unless ARGV.empty?
raise "Not the authorized pilot" unless manifest.fetch("phase") == "production_pilot_only" &&
  manifest.fetch("full_campaign_authorized") == false && manifest.fetch("preflight_ids").size == 4
raise "Already launched; inspect before resuming" if File.exist?(File.join(campaign, "pilot-launch.json"))
raise "Stopped" if File.exist?(File.join(campaign, "STOP"))
raise "Fable priority boundary reached" if Time.now >= Time.iso8601(manifest.fetch("yield_at"))
def checked(*args)
  output, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error}\n#{output}" unless status.success?
  output
end
manifest.fetch("files").each do |relative, sha|
  raise "Frozen method differs" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == sha
end
%w[/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP
   /home/petert/llm_para_campaigns/20261102-213224-glm53-opencode-high/STOP].each do |path|
  raise "Another campaign not suspended" unless File.file?(path)
end
units = checked("systemctl", "--user", "list-units", "--type=service", "--state=active,activating", "--no-legend", "--no-pager", "llm-*")
active = units.lines.map { |line| line.strip.split.first }.reject { |name| name.include?("-monitor-") }
raise "Active workloads: #{active.inspect}" unless active.empty?
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "llmtest busy" unless status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native host busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
lock.close
output = checked("systemd-run", "--user", "--unit=#{manifest.fetch('preflight_unit')}", "--description=Terra 6.1 Ultra reusable four-observation pilot",
  "--property=Type=exec", "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{campaign}/pilot.log", "--property=StandardError=append:#{campaign}/pilot.log",
  "/usr/bin/ruby", File.join(manifest.fetch("runtime_root"), "controller.rb"), "pilot")
receipt = { "launched_at" => Time.now.utc.iso8601, "unit" => manifest.fetch("preflight_unit"),
  "campaign_id" => manifest.fetch("campaign_id"), "source_commit" => manifest.fetch("source_commit"),
  "systemd_output" => output, "pilot_count" => 4, "full_campaign_authorized" => false }
File.write(File.join(campaign, "pilot-launch.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
