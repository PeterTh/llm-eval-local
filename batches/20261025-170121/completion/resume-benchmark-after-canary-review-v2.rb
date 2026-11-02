# frozen_string_literal: true

require_relative "verified-final-replica-selection"
BeamFinalReplicaSelection.verify!
require_relative "verify-revalidation-boundary"
BeamRevalidationBoundary.verify!
require_relative "benchmark-orchestration"
require_relative "review-canary-failure"
require_relative "verify-canary-runner-amendment"
require "open3"

campaign = BeamCanaryDisposition::CAMPAIGN
root = BeamCanaryDisposition::ROOT
unit = "llm-beam10-oc-benchmark-20261030.service"
receipt = File.join(campaign, "benchmark-resume-launch-v2.json")
raise "Resume already recorded" if File.exist?(receipt)
gate = JSON.parse(File.read(File.join(campaign, "benchmark-canary-gate.json")))
BeamCanaryDisposition.verify!(gate.fetch("failures"))
raise "Canary guard changed" unless BenchmarkValidationBatch.verify_partition!(root, gate.fetch("canary_ids")) == gate.fetch("guard")
raise "Measurements unexpectedly started" unless BenchmarkValidationBatch.full_results(root).keys.sort == gate.fetch("canary_ids").sort
metadata = YAML.safe_load_file(File.join(root, "benchmark/benchmark_run_metadata.yaml"))
raise "Unexpected native invocation" unless metadata.fetch("invocations") == gate.fetch("invocations")
progress_path = File.join(campaign, "benchmark-progress.json")
progress = JSON.parse(File.read(progress_path))
raise "Different interrupted state" unless progress.values_at("phase", "stopped_phase", "error") ==
  ["stopped", "verify_inputs", "RuntimeError: Campaign runner changed"]
state, status = Open3.capture2("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
raise "Benchmark remains active" unless status.success? && !%w[active activating deactivating].include?(state.strip)
archive = File.join(campaign, "benchmark-stopped-runner-provenance-progress.json")
raise "Stopped progress already retained" if File.exist?(archive)
FileUtils.cp(progress_path, archive)
names = %w[benchmark-orchestration-v3.rb benchmark-driver-v4.rb verify-canary-runner-amendment.rb resume-benchmark-after-canary-review-v2.rb]
names.each { |name| FileUtils.cp(File.join(__dir__, name), File.join(campaign, name)) }
driver = File.join(__dir__, "benchmark-driver-v4.rb")
runner = File.join(__dir__, "benchmark-orchestration-v3.rb")
BeamCanaryRunnerAmendment.verify!(runner, BenchmarkValidationBatch.campaign_data(root).fetch("artifacts").fetch("runner-snapshot.rb"))
log = File.join(campaign, "benchmark-resumed-v2-driver.log")
raise "Resume log already exists" if File.exist?(log)
raise "Resume failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Beam 1.0 OpenCode benchmarking with inspected canary program failure retained",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver)
output, status = Open3.capture2("systemctl", "--user", "show", unit,
  "-p", "ActiveState", "-p", "SubState", "-p", "InvocationID", "-p", "ExecMainStartTimestamp", "-p", "ExecMainPID")
properties = output.lines.to_h { |line| line.strip.split("=", 2) }
raise "Resume did not start" unless status.success? && properties.fetch("ActiveState") == "active"
paths = names.map { |name| File.join(__dir__, name) } + [archive,
  File.join(campaign, "benchmark-launch.json"), File.join(campaign, "benchmark-canary-gate.json"), BeamCanaryDisposition::REPORT,
  File.join(campaign, "benchmark-resume-launch.json"), BeamCanaryRunnerAmendment::REPORT]
report = { "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "completed_before_resume" => 4, "native_invocations_before_resume" => metadata.fetch("invocations"),
  "method" => "Only orchestration gate updated to honor the already inspected, source-pinned canary program failure. Native pipeline, arguments, resources, source commits and measurements unchanged. Initial full driver stopped before any additional native invocation. All four canaries reused; no retries.",
  "input_sha256" => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] } }
File.write(receipt, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
