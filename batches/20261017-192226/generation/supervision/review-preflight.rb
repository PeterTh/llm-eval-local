require "json"
require "digest"
require "open3"
require "time"

root = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
progress = JSON.parse(File.read(File.join(root, "progress.json")))
raise "Preflight is not finished" unless progress.fetch("status") == "preflight_complete"
raise "Unexpected accepted observations" unless progress.fetch("completed") == 4
gate = JSON.parse(File.read(File.join(root, "preflight-gate.json")))
raise "Infrastructure gate failed" unless gate.fetch("accepted") == true
ids = manifest.fetch("preflight_ids")
raise "Pilot selection differs" unless gate.fetch("preflights").map { |report| report.fetch("id") } == ids
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless status.exitstatus == 1 && pids.empty?

require File.join(manifest.fetch("working_directory"), "lib/opencode_generation_observation")
profile = manifest.fetch("models").fetch("gpt-6.1-sol-oc-medium")
reports = ids.map do |id|
  report = OpenCodeGenerationObservation.read(File.join(manifest.fetch("persistent_results"), id),
    timeout_seconds: manifest.fetch("per_run_timeout_seconds"), model: profile.fetch("model"),
    effort: profile.fetch("reasoning_effort"), version: manifest.fetch("opencode_version"),
    baseline: gate.fetch("preflights").first)
  raise "Retained report differs" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  raise "Incomplete usage" unless report.fetch("usage_complete") && report.fetch("outcome") == "completed"
  cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
  raise "Cleanup was not verified" unless cleanup.fetch("verified_empty") && cleanup.fetch("id") == id
  report
end
raise "Resolved model changed between pilots" unless reports.map { |report| report.fetch("resolved_model") }.uniq.size == 1
raise "Effective tools changed between pilots" unless reports.map { |report| report.fetch("tools") }.uniq.size == 1
regression = File.read(File.join(root, "regression-tests.log"))
raise "Regression suite not passing" unless regression.include?("267 runs, 1542 assertions, 0 failures, 0 errors, 0 skips")

review = {
  "reviewed_at" => Time.now.utc.iso8601,
  "accepted" => true,
  "original_results_reused" => true,
  "ids" => ids,
  "criterion" => "Harness identity, capability isolation, native accounting, task clocks and cleanup only. No generated-program correctness or performance selection.",
  "method_commit" => manifest.fetch("source_commit"),
  "sequential_source_commit" => manifest.fetch("sequential_source_commit"),
  "model" => profile.fetch("model"),
  "reasoning_effort" => profile.fetch("reasoning_effort"),
  "harness_version" => manifest.fetch("opencode_version"),
  "resolved_model_identical" => true,
  "effective_tools" => reports.first.fetch("tools"),
  "native_usage_cross_check" => "Native SSE step-finish counters match native session counters for every request. CLI evidence matches except its recorded terminal-accounting omission; original transcripts are unchanged.",
  "raw_generation_seconds" => reports.sum { |report| report.fetch("raw_total_seconds") }.round(2),
  "total_tokens" => reports.sum { |report| report.fetch("total_tokens") },
  "retry_count" => reports.sum { |report| report.fetch("retry_count") },
  "cleanup_verified_for_all_pilots" => true,
  "account_idle_at_review" => true,
  "tests" => { "runs" => 267, "assertions" => 1542, "failures" => 0, "errors" => 0, "skips" => 0 },
  "tests_log_sha256" => Digest::SHA256.file(File.join(root, "regression-tests.log")).hexdigest,
  "gate_sha256" => Digest::SHA256.file(File.join(root, "preflight-gate.json")).hexdigest,
  "remaining_observations" => manifest.fetch("expected_runs") - reports.size,
  "incidents" => ["incidents/pilot-audit-visibility", "incidents/pilot-postprocessing"],
  "next_stage" => "Launch remaining observations serially; retain all four pilots. Validation follows completion and preservation of originals."
}
destination = File.join(root, "preflight-review.json")
raise "Review already exists" if File.exist?(destination)
File.write(destination, JSON.pretty_generate(review) + "\n")
puts JSON.pretty_generate(review)
