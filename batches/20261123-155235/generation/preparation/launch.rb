# frozen_string_literal: true
require "json"
require "open3"
require "time"
require "digest"
action = ARGV.fetch(0)
raise "Use preflight or run" unless %w[preflight run].include?(action) && ARGV.size == 1
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
receipt = File.join(campaign, "#{action}-launch.json")
raise "Already launched; inspect before resuming" if File.exist?(receipt)
raise "Campaign stopped" if File.exist?(File.join(campaign, "STOP"))
def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end
raise "Wrong campaign scope" unless manifest.fetch("expected_runs") == 440 && manifest.fetch("per_run_timeout_seconds") == 14400 && manifest.fetch("full_campaign_authorized")
manifest.fetch("files").each { |path,sha| raise "Method changed" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"),path)).hexdigest == sha }
manifest.fetch("orchestration_files").each { |path,sha| raise "Controller changed" unless Digest::SHA256.file(File.join(manifest.fetch("runtime_root"),path)).hexdigest == sha }
native = JSON.parse(File.read(File.join(campaign,"preparation/filesystem-preflight.json")))
raise "Native checks incomplete" unless native.fetch("lifecycle_exit_status").zero? && native.fetch("private_state_removed")
raise "Method unpublished" unless checked("git","-C","/home/petert/llm_eval/experiment","ls-remote","--exit-code","origin","refs/heads/codex").strip == "#{manifest.fetch('source_commit')}\trefs/heads/codex"
units = checked("systemctl","--user","list-units","--type=service","--state=active,activating","--no-legend","--no-pager","llm-*")
active = units.lines.map { |line| line.strip.split.first }.reject { |name| name.include?("-monitor-") }
raise "Active native workload: #{active.inspect}" unless active.empty?
pids, status = Open3.capture2("pgrep","-u","llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock","a")
raise "Host locked" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
if action == "run"
  gate = JSON.parse(File.read(File.join(campaign,"preflight-gate.json")))
  review = JSON.parse(File.read(File.join(campaign,"preflight-review.json")))
  raise "Pilot gate failed" unless gate.fetch("accepted") && gate.fetch("preflights").map { |row| row.fetch("id") } == manifest.fetch("preflight_ids")
  raise "Pilot review incomplete" unless review.fetch("passed") && review.fetch("retained_pilot_reexecuted") == false
else
  raise "Pilot already has observations" unless Dir[File.join(campaign,"observations/*.json")].empty?
end
unit = manifest.fetch(action == "preflight" ? "preflight_unit" : "generation_unit")
lock.close
output = checked("systemd-run","--user","--unit=#{unit}","--description=Astra/Sol 6.2 Medium #{action}",
  "--property=Type=exec","--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{campaign}/#{action}.log","--property=StandardError=append:#{campaign}/#{action}.log",
  "/usr/bin/ruby",File.join(manifest.fetch("runtime_root"),"controller.rb"),action)
record = {"launched_at"=>Time.now.utc.iso8601,"action"=>action,"unit"=>unit,"campaign_id"=>manifest.fetch("campaign_id"),
  "source_commit"=>manifest.fetch("source_commit"),"driver_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,"systemd_output"=>output}
File.write(receipt,JSON.pretty_generate(record)+"\n")
if action == "run"
  monitor = manifest.fetch("monitor_unit").delete_suffix(".service")
  monitor_output = checked("systemd-run","--user","--unit=#{monitor}","--description=Four-hour Astra/Sol 6.2 status",
    "--on-active=4h","--on-unit-active=4h","--timer-property=AccuracySec=1min","--property=Type=oneshot",
    "--property=StandardOutput=append:#{campaign}/monitor.log","--property=StandardError=append:#{campaign}/monitor.log",
    "/usr/bin/ruby",File.join(manifest.fetch("runtime_root"),"monitor.rb"))
  File.write(File.join(campaign,"monitor-launch.json"),JSON.pretty_generate({"launched_at"=>Time.now.utc.iso8601,"timer"=>manifest.fetch("monitor_timer"),"cadence_hours"=>4,"output"=>monitor_output,"notifies_assistant"=>false})+"\n")
end
puts JSON.pretty_generate(record)
