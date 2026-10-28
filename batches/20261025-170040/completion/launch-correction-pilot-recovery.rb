# frozen_string_literal: true
require "json"
require "open3"
require "fileutils"
require "digest"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
unit = "llm-haiku55-oc-correction-pilot-20261028.service"
receipt = File.join(campaign, "correction-pilot-recovery-launch.json")
raise "Recovery already launched" if File.exist?(receipt)
state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "LoadState", "-p", "ExecMainStatus")
raise "Cannot inspect stopped unit" unless status.success?
properties = state.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Pilot still active" if %w[active activating deactivating].include?(properties.fetch("ActiveState"))
if properties.fetch("ActiveState") == "failed"
  raise "Cannot clear failed service state" unless system("systemctl", "--user", "reset-failed", unit)
end
driver = File.join(__dir__, "resume-correction-pilot-driver.rb")
log = File.join(campaign, "correction-pilot-recovery-driver.log")
raise "Recovery log already exists" if File.exist?(log)
[__FILE__, driver].each { |path| FileUtils.cp(path, campaign) }
raise "Recovery launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Haiku timing correction pilot: bounded serial recovery after HTTP 429",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver)
current, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "InvocationID")
raise "Cannot inspect recovery service" unless status.success?
properties_now = current.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Recovery did not start" unless properties_now.fetch("ActiveState") == "active"
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties_now,
  "prior_service_state" => properties, "driver_sha256" => Digest::SHA256.file(driver).hexdigest,
  "original_failure" => "HTTP 429 Too Many Requests; no reset time or specific quota code in retained CLI events",
  "successful_bounded_retry" => "nbody_claude-haiku-5.5-oc-medium_mpi_r2/attempt-05",
  "retained_proposals" => 6, "unfinished_pilot_proposals" => 10,
  "proposal_workers" => 1, "attempts_per_invocation" => 1,
  "model_and_scientific_policy_changed" => false,
  "documentation" => "https://developers.openai.com/api/docs/guides/rate-limits"
}
File.write(receipt, JSON.pretty_generate(report) + "\n", mode: "wx")
puts JSON.pretty_generate(report)
