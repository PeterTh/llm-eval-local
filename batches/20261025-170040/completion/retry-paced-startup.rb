# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
receipt_path = File.join(campaign, "correction-pilot-paced-launch.json")
receipt = JSON.parse(File.read(receipt_path))
driver = File.join(__dir__, "paced-correction-driver.rb")
raise "Driver changed" unless Digest::SHA256.file(driver).hexdigest == receipt.fetch("driver_sha256")
unit = receipt.fetch("unit")
state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
raise "Service active or unavailable" unless status.success? && %w[inactive failed].include?(state.strip)
raise "Paced worker progressed" if File.exist?(File.join(campaign, "correction-pilot-paced-progress.json"))
log = File.join(campaign, "correction-pilot-paced-driver.log")
raise "Not the expected startup-only failure" unless File.read(log).include?("undefined method `parse' for Time:Class")
report_path = File.join(campaign, "correction-pilot-paced-startup-recovery.json")
raise "Already recovered startup" if File.exist?(report_path)
before_log_sha = Digest::SHA256.file(log).hexdigest
FileUtils.cp(__FILE__, campaign)
FileUtils.cp(File.join(__dir__, "launch-paced-corrections.rb"), File.join(campaign, "launch-paced-corrections-current.rb"))
raise "Cannot clear failed unit" if state.strip == "failed" && !system("systemctl", "--user", "reset-failed", unit)
raise "Startup recovery failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Haiku paced correction pilot with time standard library preloaded",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", "-rtime", driver, "trial")
properties, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "InvocationID")
raise "Cannot inspect recovered unit" unless status.success?
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit,
  "properties" => properties.lines.to_h { |line| line.chomp.split("=", 2) },
  "original_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest,
  "driver_sha256" => receipt.fetch("driver_sha256"), "startup_failure_log_sha256" => before_log_sha,
  "change" => "Preload Ruby's time standard library with -rtime; immutable paced driver, receipt, all proposals and scientific method unchanged. Startup failed before inference."
}
File.write(report_path, JSON.pretty_generate(report) + "\n", mode: "wx")
puts JSON.pretty_generate(report)
