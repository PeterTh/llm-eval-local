# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "time"

root = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
queue_root = "/home/petert/llm_para_campaigns/20261025-170159-opencode-go-queue"
incident = File.join(root, "incidents/20261029-prompt-rendering-failure")
amendment = JSON.parse(File.read(File.join(incident, "admission-amendment.json")))
manifest_path = File.join(root, "campaign.json")
manifest = JSON.parse(File.read(manifest_path))
queue_path = File.join(queue_root, "queue.json")
queue = JSON.parse(File.read(queue_path))
deadline = Time.iso8601("2026-10-30T17:00:00Z")
raise "Fable reset now has priority" if Time.now >= deadline
raise "Resume already attempted" if File.exist?(File.join(incident, "resume.json"))
raise "Queue is held" if File.exist?(File.join(queue_root, "STOP"))
stop = File.join(root, "STOP")
raise "Unexpected hold" unless File.read(stop).start_with?("Held pending user adjudication of Beam prompt-rendering failure")
checked = lambda do |*args|
  output, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error}" unless status.success?
  output
end
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Test account busy" unless status.exitstatus == 1 && pids.empty?
raise "Generation still running" if checked.call("systemctl", "--user", "show", queue.fetch("generation_unit"), "-p", "ActiveState", "--value").strip == "active"
units = checked.call("systemctl", "--user", "list-units", "--type=service", "--state=active,activating", "--no-legend", "--no-pager", "llm-*")
raise "Another campaign is active" unless units.strip.empty?
raise "Fable suspension guard missing" unless File.file?(File.join(manifest.fetch("paused_campaign").fetch("path"), "STOP"))
raise "Fable deadline guard not active" unless checked.call("systemctl", "--user", "show", "llm-beam10-fable-boundary-20261030.timer", "-p", "ActiveState", "--value").strip == "active"
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Another native workload is active" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
at_exit { lock.close unless lock.closed? }
manifest.fetch("files").each do |name, sha|
  raise "Frozen generation changed: #{name}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), name)).hexdigest == sha
  expected = amendment.fetch("replaced_admission_files").dig(name, "after") || sha
  raise "Admission snapshot changed: #{name}" unless Digest::SHA256.file(File.join(__dir__, name)).hexdigest == expected
end
manifest.fetch("benchmark_files").each do |name, sha|
  raise "Sequential input changed" unless Digest::SHA256.file(File.join(manifest.fetch("runtime_root"), "benchmarks", name)).hexdigest == sha
end
raise "OpenCode binary changed" unless Digest::SHA256.file(manifest.fetch("opencode_binary")).hexdigest == manifest.fetch("opencode_binary_sha256")
require File.join(__dir__, "tools/opencode_campaign_queue")
driver = GenerationCampaign.new(root)
ids = Dir[File.join(root, "observations/*.json")].map { |path| File.basename(path, ".json") }
raise "Retained scope differs" unless ids.size == 115
gate = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflights").first
ids.each { |id| driver.observation(id, baseline: gate) }
access = JSON.parse(checked.call("su", "-", "llmtest", "-c", Shellwords.join([
  "ruby", File.join(manifest.fetch("working_directory"), "tools/opencode_go_access.rb"),
  "opencode-go/beam-free", manifest.fetch("opencode_auth_file") ])))
raise "Free route unavailable" unless access.values_at("available", "allowed", "free_only") == [true, true, true]
File.write(File.join(incident, "access-before-resume.json"), JSON.pretty_generate(access) + "\n", mode: "wx")
FileUtils.cp(queue_path, File.join(incident, "queue-before-resume.json"))
FileUtils.cp(manifest_path, File.join(incident, "campaign-before-resume.json"))
stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
unit = "llm-opencode-go-queue-resume-#{stamp}.service"
monitor = "llm-beam10-resume-monitor-#{stamp}"
previous_unit = queue.fetch("generation_unit")
queue.merge!("generation_unit" => unit, "monitor_unit" => "#{monitor}.service", "monitor_timer" => "#{monitor}.timer",
  "controller_directory" => __dir__, "admission_source_commit" => amendment.fetch("admission_source_commit"),
  "admission_amendment" => File.join(incident, "admission-amendment.json"))
manifest.merge!("generation_unit" => unit, "monitor_unit" => "#{monitor}.service", "monitor_timer" => "#{monitor}.timer")
File.write(queue_path, JSON.pretty_generate(queue) + "\n")
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
OpenCodeCampaignQueue.new(queue_root)
File.rename(stop, File.join(incident, "STOP-released"))
lock.close
runner = File.join(__dir__, "tools/opencode_campaign_queue.rb")
checked.call("systemd-run", "--user", "--unit=#{unit}", "--description=Resume Beam after retaining approved protocol failure without retry",
  "--property=Type=exec", "--property=WorkingDirectory=#{__dir__}",
  "--property=StandardOutput=append:#{queue_root}/generation.log", "--property=StandardError=append:#{queue_root}/generation.log",
  "/usr/bin/ruby", runner, "run", queue_root)
properties = checked.call("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "InvocationID").lines.to_h { |line| line.strip.split("=", 2) }
raise "Controller did not start" unless properties.fetch("ActiveState") == "active" && properties.fetch("MainPID").to_i > 1
checked.call("systemd-run", "--user", "--unit=#{monitor}", "--description=Four-hour resumed Beam status",
  "--on-active=4h", "--on-unit-active=4h", "--timer-property=AccuracySec=1min", "--property=Type=oneshot",
  "--property=StandardOutput=append:#{queue_root}/monitor.log", "--property=StandardError=append:#{queue_root}/monitor.log",
  "/usr/bin/ruby", runner, "status", queue_root)
record = {
  "resumed_at" => Time.now.utc.iso8601, "unit" => unit, "previous_unit" => previous_unit, "properties" => properties,
  "retained_observations" => ids.size, "retry_ids" => [], "unstarted_observations" => 105,
  "fable_priority_reset" => deadline.iso8601, "monitor_timer" => "#{monitor}.timer",
  "generation_runtime_and_settings_unchanged" => true,
  "admission_amendment_sha256" => Digest::SHA256.file(File.join(incident, "admission-amendment.json")).hexdigest,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
FileUtils.cp(__FILE__, File.join(incident, File.basename(__FILE__)))
File.write(File.join(incident, "resume.json"), JSON.pretty_generate(record) + "\n", mode: "wx")
puts JSON.pretty_generate(record)
