# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

scratch = File.dirname(__FILE__)
previous = "/tmp/haiku55-evaluation-20261014.ZqhO2v"
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
repository = "/home/petert/llm_eval/experiment"
commit = "5a64edb58cdfdb2d53a6b9fac4d6eab1c83fedb5"
helper = "tools/timing_audit/bin/benchmark_validation_batch.rb"
bytes, status = Open3.capture2("git", "-C", repository, "show", "#{commit}:#{helper}")
raise "Cannot read committed orchestration" unless status.success?
original_sha = Digest::SHA256.hexdigest(bytes)
{
  'require_relative "../../../lib/local_evaluation"' => "require #{File.join(scratch, 'experiment/lib/local_evaluation').inspect}",
  'require_relative "../lib/timing_audit"' => "require #{File.join(scratch, 'experiment/tools/timing_audit/lib/timing_audit').inspect}"
}.each do |before, after|
  raise "Missing dependency binding" unless bytes.scan(before).size == 1
  bytes = bytes.sub(before, after)
end
orchestration = File.join(scratch, "benchmark-orchestration.rb")
raise "Orchestration already exists" if File.exist?(orchestration)
File.binwrite(orchestration, bytes)
replacements = {
  File.join(previous, "experiment/tools/timing_audit/bin/benchmark_validation_batch") => orchestration.delete_suffix(".rb"),
  previous => scratch,
  "/home/petert/llm_para_campaigns/20261012-111947-haiku55-medium/evaluation" => campaign,
  "20261014-haiku55" => "20261015-sonnet55",
  "llm-haiku55-benchmark-monitor-20261014" => "llm-sonnet55-benchmark-monitor-20261015",
  "llm-haiku55-benchmark-20261014" => "llm-sonnet55-benchmark-20261015",
  "claude-haiku-5.5-cc-medium" => "claude-sonnet-5.5-cc-medium",
  "Haiku55BenchmarkETA" => "Sonnet55BenchmarkETA",
  "Haiku 5.5" => "Sonnet 5.5",
  "588bbc17d3fd0874d4c43906ca76403107999434742c9d5521cd443f7ac9bddd" =>
    "76425ec9f387e5a185c235e197d1e43f2d1e3078a5c41223476f6ad216697e2f"
}.sort_by { |before, _after| -before.size }.to_h
names = %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb
  benchmark-eta.rb benchmark-monitor.rb test-benchmark-eta.rb]
receipts = names.map do |name|
  input = File.join(previous, name)
  adapted = File.binread(input)
  replacements.each { |before, after| adapted = adapted.gsub(before, after) }
  adapted = adapted.gsub(/\b219\b/, "215")
  if name == "canary-driver.rb"
    marker = 'canary_model: "claude-sonnet-5.5-cc-medium")'
    raise "Missing canary selection" unless adapted.include?(marker)
    adapted = adapted.sub(marker, 'canary_model: "claude-sonnet-5.5-cc-medium", canary_fallback_benchmarks: ["cholesky"])')
  elsif name == "verify-benchmark-records.rb"
    adapted = adapted.sub(/^expected_canaries = .+$/, 'expected_canaries = BenchmarkValidationBatch.canary_ids(unchanged, "claude-sonnet-5.5-cc-medium", fallback_benchmarks: ["cholesky"])')
    adapted = adapted.sub('"validation_failed" => 1', '"validation_failed" => 5')
    marker = '"validation_failure_ids" => ["nbody_claude-sonnet-5.5-cc-medium_hybrid_r2"]'
    raise "Missing historical failure fixture" unless adapted.include?(marker)
    adapted = adapted.sub(marker, '"validation_failure_ids" => JSON.parse(File.read(File.join(campaign, "validation-completion-review.json"))).fetch("failures").map { |row| row.fetch("program_id") }')
  end
  raise "Historical identity remains" if adapted.match?(/haiku55|Haiku|claude-haiku|20261012-111947/)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  File.binwrite(output, adapted)
  out, err, result = Open3.capture3("ruby", "-c", output)
  raise "Syntax error: #{out}#{err}" unless result.success?
  { "file" => name, "template" => input, "template_sha256" => Digest::SHA256.file(input).hexdigest,
    "adapted_sha256" => Digest::SHA256.file(output).hexdigest }
end
receipt = {
  "prepared_at" => Time.now.utc.iso8601,
  "orchestration_source_commit" => commit, "orchestration_source_path" => helper,
  "orchestration_source_sha256" => original_sha,
  "execution_snapshot_sha256" => Digest::SHA256.file(orchestration).hexdigest,
  "snapshot_changes" => "Only the two require paths rebound to the unchanged frozen native pipeline and audit helper.",
  "canary_preference" => ["black-scholes", "cholesky"],
  "canary_policy" => "Explicit fallback per backend only when no unchanged valid black-scholes exists; choose lowest eligible repetition and retain the measurement without repetition.",
  "native_pipeline_sha256" => "4f719f102e7e1ed7b556e2e9f7885534db57786646b9e01c718d0f4cf83ed83d",
  "regression_tests" => { "seed" => 20261016, "tests" => 240, "assertions" => 1445, "failures" => 0, "errors" => 0, "skips" => 0 },
  "drivers" => receipts
}
report = File.join(scratch, "benchmark-driver-template-reuse.json")
File.write(report, JSON.pretty_generate(receipt) + "\n")
(names + ["benchmark-orchestration.rb", "prepare-benchmark-drivers.rb", File.basename(report)]).each do |name|
  destination = File.join(campaign, name)
  raise "Persistent driver exists: #{name}" if File.exist?(destination)
  FileUtils.cp(File.join(scratch, name), destination)
end
puts JSON.pretty_generate(receipt)
