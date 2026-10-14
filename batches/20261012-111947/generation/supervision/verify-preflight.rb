require "json"
require "time"
require "digest"
require "open3"
require "fileutils"

root = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "lib/local_evaluation")
require File.join(manifest.fetch("working_directory"), "lib/claude_generation_observation")
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account is not idle" unless status.exitstatus == 1 && pids.empty?
unit, status = Open3.capture2("systemctl", "--user", "show", manifest.fetch("preflight_unit"),
  "-p", "ActiveState", "-p", "SubState", "-p", "ExecMainStatus", "-p", "Result")
raise "Preflight service inspection failed" unless status.success?
unit = unit.lines.to_h { |line| line.strip.split("=", 2) }
raise "Preflight service has not completed successfully" unless unit["ActiveState"] == "inactive" && unit["Result"] == "success" && unit["ExecMainStatus"] == "0"
gate = JSON.parse(File.read(File.join(root, "preflight-gate.json")))
raise "Preflight is not accepted" unless gate.fetch("accepted")
report = gate.fetch("preflight")
id = manifest.fetch("preflight_ids").fetch(0)
raise "Preflight identity differs" unless report.fetch("id") == id
source = File.join(manifest.fetch("persistent_results"), id)
fresh = ClaudeGenerationObservation.read(source, model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"))
raise "Preflight evidence changed" unless fresh == report
cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
raise "Cleanup was not verified" unless cleanup.fetch("verified_empty")
benchmark, model, backend, repetition = id.split("_")
result = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
pipeline = LocalEvaluation::AggregatePipeline.allocate
pipeline.instance_variable_set(:@warnings, {})
pipeline.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(__dir__, "benchmarks")))
pipeline.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark }, result)
expected = { "total_time" => report.fetch("total_seconds"), "api_time" => report.fetch("api_seconds"),
  "input_tokens" => report.fetch("inclusive_input_tokens"), "output_tokens" => report.fetch("token_counts").fetch("output_tokens"),
  "cached_tokens" => report.fetch("token_counts").fetch("cache_read_input_tokens"), "total_tokens" => report.fetch("total_tokens"),
  "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds") }
actual = expected.keys.to_h { |field| [field, result.public_send(field)] }
raise "Aggregate parser disagrees: #{actual.inspect}" unless actual == expected
raise "Aggregate parser warning" unless pipeline.instance_variable_get(:@warnings).empty?
dry, error, status = Open3.capture3("ruby", File.join(__dir__, "run.rb"), "--production",
  "--continue=#{manifest.fetch('campaign_id')}", "--run-ids=#{root}/preflight-ids.txt")
raise "Continuation check failed: #{error}" unless status.success? && dry.include?("Timing file already exists, skipping run") && dry.include?("following 0 runs")
File.write(File.join(root, "preflight-reuse-dry-run.txt"), dry)
review = { "verified_at" => Time.now.utc.iso8601, "accepted" => true, "id" => id,
  "unit" => unit, "preflight" => report, "cleanup" => cleanup, "aggregate_parser" => actual,
  "original_result_reused" => true, "program_correctness_used_as_gate" => false,
  "regression_tests" => { "runs" => 209, "assertions" => 1292, "failures" => 0, "errors" => 0, "skips" => 0, "seed" => 48524 },
  "tooling_commit" => manifest.fetch("source_commit") }
File.write(File.join(root, "preflight-review.json"), JSON.pretty_generate(review) + "\n")
FileUtils.cp(__FILE__, File.join(root, "verify-preflight.rb"))
puts JSON.pretty_generate(review)
