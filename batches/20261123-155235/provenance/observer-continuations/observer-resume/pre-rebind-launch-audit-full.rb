# frozen_string_literal: true
require "json"
require "open3"
require "fileutils"
require "digest"
require "time"

scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
unit = "llm-gpt62-medium-timing-full-20261125.service"
receipt = File.join(campaign, "audit-full-launch.json")
raise "Full audit already launched" if File.exist?(receipt)
progress = JSON.parse(File.read(File.join(campaign, "audit-pilot-progress.json")))
raise "Pilot not ready" unless progress.fetch("phase") == "awaiting_primary_pilot_quality_review"
state, = Open3.capture2("systemctl", "--user", "show", "llm-gpt62-medium-timing-pilot-20261125.service", "--property=ActiveState", "--value")
raise "Pilot still active" if %w[active activating reloading].include?(state.strip)
policy = JSON.parse(File.read(File.join(campaign, "review-policy.json")))
raise "Wrong review policy" unless policy.fetch("policy") == "luna_first_uncertainty_or_disagreement_v1"
driver = File.join(scratch, "audit-full-driver-policy.rb")
raise "Full driver changed" unless Digest::SHA256.file(driver).hexdigest == policy.fetch("driver_sha256")
pilot = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
raise "Review CLI changed" unless File.realpath("/home/petert/.local/bin/codex") == pilot.fetch("review_cli_path") &&
  Digest::SHA256.file(pilot.fetch("review_cli_path")).hexdigest == pilot.fetch("review_cli_sha256")
log = File.join(campaign, "audit-full-driver.log")
raise "Full audit log already exists" if File.exist?(log)
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
command = ["systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Astra 6.2 and Sol 6.2 Medium source-only timing audit",
  "--property=WorkingDirectory=#{scratch}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
  "/usr/bin/ruby", driver]
raise "Full audit launch failed" unless system(*command)
out, status = Open3.capture2("systemctl", "--user", "show", unit,
  "-p", "ActiveState", "-p", "SubState", "-p", "InvocationID", "-p", "ExecMainStartTimestamp")
raise "Full audit service inspection failed" unless status.success?
properties = out.lines.to_h { |line| line.strip.split("=", 2) }
raise "Full audit did not start" unless properties.fetch("ActiveState") == "active"
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "policy_sha256" => Digest::SHA256.file(File.join(campaign, "review-policy.json")).hexdigest,
  "driver_sha256" => Digest::SHA256.file(driver).hexdigest,
  "review_cli_sha256" => pilot.fetch("review_cli_sha256"),
  "review_workers" => policy.fetch("review_workers"), "pilot_results_reused" => true,
  "review_workers_source_only" => true, "review_workers_can_compile_or_execute" => false,
  "stronger_selection" => "Only uncertainty or disagreement; no blanket adjudication"
}
File.write(receipt, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
