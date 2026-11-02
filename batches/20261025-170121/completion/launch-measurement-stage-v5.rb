# frozen_string_literal: true

require_relative "verified-final-replica-selection"
replica_resolution = BeamFinalReplicaSelection.verify!
require "json"
require "yaml"
require "open3"
require "fileutils"
require "digest"
require "time"

require_relative "verified-external-validation"
BeamExternalValidation.verify!
stage = ARGV.fetch(0)
raise "Invalid stage" unless ARGV.size == 1 && %w[revalidation canary benchmark].include?(stage)
scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
unit = "llm-beam10-oc-#{stage}-20261030.service"
receipt = File.join(campaign, "#{stage}-launch.json")
raise "Stage already launched" if File.exist?(receipt)
read = ->(name) { JSON.parse(File.read(File.join(campaign, name))) }
case stage
when "revalidation"
  gate_name = "correction-commit.json"
  gate = read.call(gate_name)
  raise "Correction count changed" unless gate.fetch("corrections") == replica_resolution.fetch("corrections")
  prior_unit = "llm-beam10-oc-correction-resumed-20261101.service"
  progress = read.call("correction-resumed-progress-20261101.json")
  raise "Correction review incomplete" unless progress.fetch("phase") == "awaiting_correction_commit_review" && progress.fetch("unresolved_ids").empty?
when "canary"
  gate_name = "revalidation-completion-review.json"
  gate = read.call(gate_name)
  raise "Revalidation incomplete" unless gate.fetch("verification") == "passed" && gate.fetch("native_scientific_validation_passed") == replica_resolution.fetch("corrections")
  require_relative "verify-revalidation-boundary"
  BeamRevalidationBoundary.verify!
  prior_unit = "llm-beam10-oc-revalidation-20261030.service"
when "benchmark"
  gate_name = "benchmark-canary-gate.json"
  gate = read.call(gate_name)
  raise "Canary gate failed" unless gate.fetch("quality_gate") == "passed" && gate.fetch("completed") == 4
  require_relative "review-canary-failure"
  BeamCanaryDisposition.verify!(gate.fetch("failures"))
  raise "Canary failure disposition changed" unless Digest::SHA256.file(BeamCanaryDisposition::REPORT).hexdigest == gate.fetch("canary_failure_review_sha256")
  prior_unit = "llm-beam10-oc-canary-20261030.service"
end
state, = Open3.capture2("systemctl", "--user", "show", prior_unit, "--property=ActiveState", "--value")
raise "Prior stage is active" if %w[active activating reloading].include?(state.strip)
driver = File.join(scratch, stage == "revalidation" ? "revalidation-boundary-driver.rb" : stage == "benchmark" ? "benchmark-driver-v2.rb" : "canary-driver.rb")
raise "Persistent driver changed" unless Digest::SHA256.file(driver).hexdigest == Digest::SHA256.file(File.join(campaign, File.basename(driver))).hexdigest
log = File.join(campaign, "#{stage}-driver.log")
raise "Stage log already exists" if File.exist?(log)
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
raise "Stage launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Beam 1.0 OpenCode #{stage} using unchanged native evaluation",
  "--property=WorkingDirectory=#{scratch}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver)
out, status = Open3.capture2("systemctl", "--user", "show", unit,
  "-p", "ActiveState", "-p", "SubState", "-p", "InvocationID", "-p", "ExecMainStartTimestamp", "-p", "ExecMainPID", "-p", "LimitNOFILE")
raise "Stage inspection failed" unless status.success?
properties = out.lines.to_h { |line| line.strip.split("=", 2) }
raise "Stage did not start" unless properties.fetch("ActiveState") == "active"
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "gate_path" => File.join(campaign, gate_name), "gate_sha256" => Digest::SHA256.file(File.join(campaign, gate_name)).hexdigest,
  "driver_sha256" => Digest::SHA256.file(driver).hexdigest,
  "scope" => stage == "revalidation" ? "Exactly #{replica_resolution.fetch("corrections")} timing-corrected programs" : "New batch only; 179 valid programs, four reusable canaries",
  "measurement_policy" => "Original native validation plus the additional boundary-sensitive external case; historical benchmark settings unchanged. Preserve ordinary failures, no automatic retries or historical re-execution"
}
File.write(receipt, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)

