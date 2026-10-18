# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

scratch = __dir__
previous = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
previous_scratch = "/tmp/sonnet55-evaluation-20261015.FtsY7h"
campaign = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium/evaluation"
method = File.join(scratch, "experiment")
commit = "00807fb3854ae70deb3bf4a43f931005660ffc96"
helper = "tools/timing_audit/bin/benchmark_validation_batch.rb"
bytes, status = Open3.capture2("git", "-C", method, "show", "#{commit}:#{helper}")
raise "Cannot read pinned orchestration" unless status.success?
raise "Frozen orchestration differs" unless bytes == File.binread(File.join(method, helper))
original_sha = Digest::SHA256.hexdigest(bytes)
{
  'require_relative "../../../lib/local_evaluation"' => "require #{File.join(method, 'lib/local_evaluation').inspect}",
  'require_relative "../lib/timing_audit"' => "require #{File.join(method, 'tools/timing_audit/lib/timing_audit').inspect}"
}.each do |before, after|
  raise "Missing dependency binding" unless bytes.scan(before).size == 1
  bytes = bytes.sub(before, after)
end
orchestration = File.join(scratch, "benchmark-orchestration.rb")
raise "Orchestration already exists" if File.exist?(orchestration)
File.binwrite(orchestration, bytes)
replacements = {
  previous_scratch => scratch,
  previous => campaign,
  "20261015-sonnet55" => "20261018-sol61-opencode",
  "llm-sonnet55-benchmark-monitor-20261015" => "llm-sol61-oc-benchmark-monitor-20261018",
  "llm-sonnet55-benchmark-20261015" => "llm-sol61-oc-benchmark-20261018",
  "claude-sonnet-5.5-cc-medium" => "gpt-6.1-sol-oc-medium",
  "Sonnet55BenchmarkETA" => "Sol61OpenCodeBenchmarkETA",
  "Sonnet 5.5" => "Sol 6.1 OpenCode",
  "76425ec9f387e5a185c235e197d1e43f2d1e3078a5c41223476f6ad216697e2f" =>
    "a7f8f73742ee8f43391d5e9753781323eabfe8cf60f0452e98633d47e68faf23"
}.sort_by { |before, _after| -before.size }.to_h
templates = {
  "canary-driver.rb" => "canary-driver-before-supplemental.rb",
  "benchmark-driver.rb" => "benchmark-driver-before-supplemental.rb",
  "verify-benchmark-records.rb" => "verify-benchmark-records-before-supplemental.rb",
  "benchmark-eta.rb" => "benchmark-eta.rb",
  "benchmark-monitor.rb" => "benchmark-monitor.rb",
  "test-benchmark-eta.rb" => "test-benchmark-eta.rb"
}
receipts = templates.map do |name, template|
  input = File.join(previous, template)
  adapted = File.binread(input)
  replacements.each { |before, after| adapted = adapted.gsub(before, after) }
  adapted = adapted.gsub(/\b215\b/, "219")
  adapted = adapted.gsub(', canary_fallback_benchmarks: ["cholesky"]', "")
  adapted = adapted.gsub(', fallback_benchmarks: ["cholesky"]', "")
  adapted = adapted.sub('"validation_failed" => 5', '"validation_failed" => 1')
  raise "Historical identity remains" if adapted.match?(/sonnet55|Sonnet|claude-sonnet|20261014-212207/)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  File.binwrite(output, adapted)
  out, err, result = Open3.capture3("ruby", "-c", output)
  raise "Syntax error: #{out}#{err}" unless result.success?
  { "file" => name, "template" => input, "template_sha256" => Digest::SHA256.file(input).hexdigest,
    "adapted_sha256" => Digest::SHA256.file(output).hexdigest }
end
out, err, result = Open3.capture3("ruby", "-c", orchestration)
raise "Orchestration syntax error: #{out}#{err}" unless result.success?
receipt = {
  "prepared_at" => Time.now.utc.iso8601,
  "orchestration_source_commit" => commit, "orchestration_source_path" => helper,
  "orchestration_source_sha256" => original_sha,
  "execution_snapshot_sha256" => Digest::SHA256.file(orchestration).hexdigest,
  "snapshot_changes" => "Only two require paths rebound to the frozen native pipeline and audit helper.",
  "template_policy" => "Reuse prior campaign orchestration before its campaign-specific supplemental cases; change only paths, model identity, scope counts and evidence bindings.",
  "canary_preference" => ["black-scholes"],
  "canary_policy" => "Lowest unchanged valid repetition in each backend, retained without repetition.",
  "native_pipeline_sha256" => "70d8bf3d6bc7570aafac3375d301c54b48a2a64a4020d04e7267ff108b67d9c1",
  "regression_tests" => { "seed" => 20261018, "tests" => 267, "assertions" => 1547, "failures" => 0, "errors" => 0, "skips" => 0 },
  "drivers" => receipts
}
report = File.join(scratch, "benchmark-driver-template-reuse.json")
File.write(report, JSON.pretty_generate(receipt) + "\n")
(templates.keys + ["benchmark-orchestration.rb", "prepare-benchmark-drivers.rb", File.basename(report)]).each do |name|
  destination = File.join(campaign, name)
  raise "Persistent driver exists: #{name}" if File.exist?(destination)
  FileUtils.cp(File.join(scratch, name), destination)
end
puts JSON.pretty_generate(receipt)
